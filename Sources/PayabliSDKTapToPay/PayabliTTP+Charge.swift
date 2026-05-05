import Foundation
import PayabliSDKCore

// MARK: - Charge pipeline (PRD §19.1, FR-11D)

/// Result of a `PATCH /MoneyIn/update/{id}` attempt — typed so the caller
/// sees the failure reason without re-reading logs.
private enum TTPUpdateOutcome {
    case succeeded
    case failed(reason: String)
}

@MainActor
extension PayabliTTP {

    /// Charge a transaction. v1.0 supports `.sale` only (FR-11D.1).
    ///
    /// Threads the `customer` / `order` snapshot through the 3-step flow:
    ///   1. `POST /MoneyIn/initiate` — backend mints the `paymentTransId`.
    ///   2. `provider.startReading(_:)` — NFC tap. `paymentTransId` wires as
    ///      both `merchantTransactionId` and `merchantOrderId`.
    ///   3. `PATCH /MoneyIn/update/{paymentTransId}` — only the provider
    ///      response travels; customer/order were persisted at step 1.
    public func charge(
        amount: Decimal,
        type: PayabliTTPPaymentType,
        serviceFee: Decimal = 0,
        customer: PayabliTTPCustomerData = PayabliTTPCustomerData(),
        order: PayabliTTPOrderData = PayabliTTPOrderData()
    ) async throws -> TransactionResult {
        guard type == .sale else {
            throw PayabliTTPError.invalidState(current: sessionState, attempted: "charge(non-sale)")
        }

        try await reinitializeIfNeeded()

        guard sessionState == .ready else {
            throw PayabliTTPError.notReady(current: sessionState)
        }

        let context = TTPTransactionContext(
            amount: amount,
            serviceFee: serviceFee,
            customer: customer,
            order: order
        )

        logger.info(
            "[charge] → amount=\(context.amount) serviceFee=\(context.serviceFee) " +
            "customer={firstName=\(customer.firstName ?? "<nil>") " +
            "lastName=\(customer.lastName ?? "<nil>") " +
            "customerNumber=\(customer.customerNumber ?? "<nil>")} " +
            "order={orderId=\(order.orderId ?? "<nil>") " +
            "description=\(order.orderDescription ?? "<nil>") " +
            "invoice=\(order.invoiceNumber ?? "<nil>")}"
        )

        // Step 1 — backend mints the paymentTransId.
        let paymentTransId = try await runInitiate(context: context)
        multicaster.emit(.chargeInitiated(paymentTransId: paymentTransId))

        // Step 2 — NFC tap.
        multicaster.emit(.nfcStarted)
        let invoiceNumber = context.order.invoiceNumber ?? context.order.orderId
        let readRequest = CardReadRequest(
            amount: context.amount,
            merchantTransactionId: paymentTransId,
            merchantOrderId: paymentTransId,
            merchantInvoiceNumber: invoiceNumber,
            customer: context.customer,
            order: context.order
        )
        let readResult: CardReadResult
        do {
            readResult = try await provider.startReading(readRequest)
            multicaster.emit(.nfcCompleted)
        } catch {
            multicaster.emit(.nfcFailed(error: String(describing: error)))
            // Best-effort backend notify so the transaction isn't left dangling.
            // Its outcome doesn't change what we report to the caller.
            _ = await tryUpdate(
                paymentTransId: paymentTransId,
                payload: .nfcFailure(description: String(describing: error))
            )
            throw PayabliTTPError.nfcFailed(reason: String(describing: error))
        }

        // Step 3 — success update. No offline fallback: on failure the
        // transaction stays authorized on the processor and the host must
        // reconcile manually.
        switch await tryUpdate(paymentTransId: paymentTransId, payload: .success(readResult)) {
        case .succeeded:
            multicaster.emit(.updateCompleted(paymentTransId: paymentTransId))
            return TransactionResult(paymentTransId: paymentTransId)
        case .failed(let reason):
            throw PayabliTTPError.updateFailed(reason: reason)
        }
    }

    // MARK: - Charge helpers

    /// `POST /MoneyIn/initiate`. Fails loudly if `deviceId` is missing —
    /// otherwise any later `PATCH /update/{id}` would 400 on a non-existent
    /// transaction.
    private func runInitiate(context: TTPTransactionContext) async throws -> String {
        guard let deviceId = cachedDeviceId else {
            throw PayabliTTPError.initiateFailed(
                reason: "Missing deviceId — run initialize() before charge()"
            )
        }
        return try await transactionClient.initiate(
            entryPoint: entryPoint,
            amount: context.amount,
            serviceFee: context.serviceFee,
            deviceId: deviceId,
            customer: context.customer,
            order: context.order
        )
    }

    /// Runs `PATCH /update/{paymentTransId}` with retry. 401 → one token
    /// refresh + retry (FR-11D.5). Returns a typed outcome so callers don't
    /// have to guess at `Bool` semantics.
    private func tryUpdate(
        paymentTransId: String,
        payload: TTPUpdatePayload
    ) async -> TTPUpdateOutcome {
        let body = TTPTransactionClient.updateBody(for: payload)
        let logger = self.logger
        let bodyDump = String(data: body, encoding: .utf8) ?? "<non-utf8 \(body.count) bytes>"
        let path = "/api/v2/MoneyIn/update/\(paymentTransId)"

        @Sendable func performOnce(token: String, attempt: String) async throws -> PayabliResponse {
            let request = PayabliRequest(
                method: .patch,
                path: path,
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Content-Type": "application/json"
                ],
                body: body
            )
            let headersDump = request.headers
                .map { "\($0.key): \($0.value)" }
                .sorted()
                .joined(separator: " | ")
            logger.info("[update/\(attempt)] → PATCH \(path)")
            logger.info("[update/\(attempt)] headers: \(headersDump)")
            logger.info("[update/\(attempt)] body: \(bodyDump)")
            let response = try await service.perform(request)
            let responseBody = String(data: response.body, encoding: .utf8) ?? "<non-utf8 \(response.body.count) bytes>"
            logger.info("[update/\(attempt)] ← [\(response.statusCode)] body: \(responseBody)")
            return response
        }

        do {
            try await Retry.run(policy: retryPolicy) { [retryPolicy, auth] _ in
                let token = await auth.currentAccessToken()
                var response = try await performOnce(token: token, attempt: "first")

                if response.statusCode == 401 {
                    let refreshed = try await auth.invalidateAndRefresh()
                    response = try await performOnce(token: refreshed, attempt: "refreshed")
                }

                if (200..<300).contains(response.statusCode) {
                    return
                }
                if retryPolicy.isRetryable(statusCode: response.statusCode) {
                    throw RetryableError(PayabliTTPError.updateFailed(
                        reason: "HTTP \(response.statusCode)"
                    ))
                }
                throw PayabliTTPError.updateFailed(reason: "HTTP \(response.statusCode)")
            }
            return .succeeded
        } catch {
            let reason = String(describing: error)
            multicaster.emit(.updateFailed(paymentTransId: paymentTransId, error: reason))
            return .failed(reason: reason)
        }
    }
}
