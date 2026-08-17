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
    /// Threads the `paymentDetails` / `customer` / `invoice` / `orderDescription`
    /// snapshot through the 3-step flow:
    ///   1. `POST /MoneyIn/initiate` — backend mints the `paymentTransId`.
    ///   2. `provider.startReading(_:)` — NFC tap. `paymentTransId` wires as
    ///      both `merchantTransactionId` and `merchantOrderId`.
    ///   3. `PATCH /MoneyIn/update/{paymentTransId}` — only the provider
    ///      response travels; everything else was persisted at step 1.
    public func charge(
        type: PayabliTTPPaymentType,
        paymentDetails: PayabliTTPPaymentDetails,
        customer: PayabliTTPCustomerData = PayabliTTPCustomerData(),
        invoice: PayabliTTPInvoiceData = PayabliTTPInvoiceData(),
        orderDescription: String? = nil
    ) async throws -> TransactionResult {
        guard type == .sale else {
            throw PayabliTTPError.invalidState(current: sessionState, attempted: "charge(non-sale)")
        }

        try await reinitializeIfNeeded()

        guard sessionState == .ready else {
            throw PayabliTTPError.notReady(current: sessionState)
        }

        // Match the trim/blank-to-nil semantics that `PayabliTTPCustomerData`
        // and `PayabliTTPInvoiceData` apply to their string fields, so a
        // whitespace-only description doesn't reach the wire as a padded
        // value.
        let trimmedOrderDescription = orderDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedOrderDescription = (trimmedOrderDescription?.isEmpty ?? true)
            ? nil
            : trimmedOrderDescription

        let context = TTPTransactionContext(
            paymentDetails: paymentDetails,
            customer: customer,
            invoice: invoice,
            orderDescription: cleanedOrderDescription
        )

        logChargeStart(
            paymentDetails: paymentDetails,
            customer: customer,
            invoice: invoice,
            orderDescription: cleanedOrderDescription
        )

        // Step 1 — backend mints the paymentTransId.
        let paymentTransId = try await runInitiate(context: context)
        multicaster.emit(.chargeInitiated(paymentTransId: paymentTransId))

        // Step 2 — NFC tap.
        multicaster.emit(.nfcStarted)
        let readRequest = CardReadRequest(
            amount: context.paymentDetails.amount,
            merchantTransactionId: paymentTransId,
            merchantOrderId: paymentTransId,
            merchantInvoiceNumber: context.invoice.invoiceNumber,
            customer: context.customer,
            invoice: context.invoice
        )
        let readResult: CardReadResult
        let generation = readerSessionGeneration
        do {
            readResult = try await provider.startReading(readRequest)
            multicaster.emit(.nfcCompleted)
        } catch {
            multicaster.emit(.nfcFailed(error: String(describing: error)))

            // A dead reader session is repaired only by re-initializing, and
            // `reinitializeIfNeeded()` does nothing while the state says `.ready`.
            //
            // Only if the reader that failed is still the current one.
            // `startReading` suspends, so an `initialize()` in that window can
            // prepare a replacement and return to `.ready`, and expiring then
            // would kill a healthy session over a dead one's failure.
            if generation == readerSessionGeneration,
               readerFailureInvalidatesSession(error),
               sessionManager.transition(to: .sessionExpired)
            {
                syncPublished()
                multicaster.emit(.sessionExpired)
            }

            // Best-effort backend notify so the transaction isn't left dangling.
            // Its outcome doesn't change what we report to the caller.
            _ = await tryUpdate(
                paymentTransId: paymentTransId,
                payload: .nfcFailure(description: String(describing: error))
            )
            throw error as? PayabliTTPError
                ?? PayabliTTPError.nfcFailed(reason: String(describing: error))
        }

        // Step 3 — success update. No offline fallback: on failure the
        // transaction stays authorized on the processor and the host must
        // reconcile manually.
        switch await tryUpdate(paymentTransId: paymentTransId, payload: .success(readResult)) {
        case .succeeded:
            multicaster.emit(.updateCompleted(paymentTransId: paymentTransId))
            return TransactionResult(paymentTransId: paymentTransId)
        case let .failed(reason):
            throw PayabliTTPError.updateFailed(reason: reason)
        }
    }

    /// `@objc` companion to `charge(type:paymentDetails:customer:invoice:orderDescription:)`.
    ///
    /// ObjC / MAUI / Flutter / RN consumers express:
    ///   - `type` as the raw value of `PayabliTTPPaymentType` (`Int`); falls
    ///     back to `.sale` if the value is unknown — v1.0 only supports
    ///     `.sale = 0` so this is the practical identity.
    ///   - `paymentDetails` as the `*ObjC` companion class (non-null).
    ///   - `customer` and `invoice` as their `*ObjC` companion classes; pass
    ///     `nil` for "no customer / no invoice provided" (equivalent to
    ///     passing the default-initialized Swift struct).
    ///   - `orderDescription` as an optional `String`.
    ///
    /// On success the completion is invoked with a non-nil
    /// `PayabliTTPTransactionResultObjC` and `nil` error. On failure the
    /// completion receives a nil result and an `NSError` (domain
    /// `"com.payabli.ttp"` for typed `PayabliTTPError`s). The completion is
    /// always invoked on the main thread.
    @objc public func charge(
        type: Int,
        paymentDetails: PayabliTTPPaymentDetailsObjC,
        customer: PayabliTTPCustomerDataObjC?,
        invoice: PayabliTTPInvoiceDataObjC?,
        orderDescription: String?,
        completion: @escaping (PayabliTTPTransactionResultObjC?, NSError?) -> Void
    ) {
        let paymentType = PayabliTTPPaymentType(rawValue: type) ?? .sale
        let swiftDetails = paymentDetails.toSwift()
        let swiftCustomer = customer?.toSwift() ?? PayabliTTPCustomerData()
        let swiftInvoice = invoice?.toSwift() ?? PayabliTTPInvoiceData()

        Task { @MainActor in
            do {
                let result = try await self.charge(
                    type: paymentType,
                    paymentDetails: swiftDetails,
                    customer: swiftCustomer,
                    invoice: swiftInvoice,
                    orderDescription: orderDescription
                )
                completion(PayabliTTPTransactionResultObjC(result), nil)
            } catch {
                completion(nil, error.toPayabliNSError())
            }
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
            deviceId: deviceId,
            paymentDetails: context.paymentDetails,
            customer: context.customer,
            invoice: context.invoice,
            orderDescription: context.orderDescription
        )
    }

    /// Runs `PATCH /update/{paymentTransId}` with retry. Bearer auth and
    /// 401 refresh-and-retry are delegated to `session.transport`
    /// (FR-11D.5). Returns a typed outcome so callers don't have to guess
    /// at `Bool` semantics.
    private func tryUpdate(
        paymentTransId: String,
        payload: TTPUpdatePayload
    ) async -> TTPUpdateOutcome {
        let body = TTPTransactionClient.updateBody(for: payload)
        let logger = self.logger
        let path = "/api/v2/MoneyIn/update/\(paymentTransId)"
        let transport = self.session.transport

        @Sendable func performOnce(attempt: String) async throws -> PayabliResponse {
            let request = PayabliRequest(
                method: .patch,
                path: path,
                headers: ["Content-Type": "application/json"],
                body: body
            )
            // The success body carries the provider's whole response, and with
            // it `paymentTokens.tokenData` and the card's expiry. Size only.
            logger.info("[update/\(attempt)] → PATCH \(path) bytes=\(body.count)")
            let response = try await transport.perform(request)
            logger.info("[update/\(attempt)] ← [\(response.statusCode)] bytes=\(response.body.count)")
            return response
        }

        do {
            try await Retry.run(policy: retryPolicy) { [retryPolicy] attempt in
                let response = try await performOnce(attempt: String(attempt))

                if (200 ..< 300).contains(response.statusCode) {
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

    /// Two lines: the charge summary, then which customer fields the caller
    /// populated. No customer value is emitted at any privacy level.
    private func logChargeStart(
        paymentDetails: PayabliTTPPaymentDetails,
        customer: PayabliTTPCustomerData,
        invoice: PayabliTTPInvoiceData,
        orderDescription: String?
    ) {
        // Charge metadata. The single-argument overload renders the whole string
        // `.public`, so only fields that carry no subject belong in it.
        logger.info(
            "[charge] → amount=\(paymentDetails.amount) serviceFee=\(paymentDetails.serviceFee) " +
                "currency=\(paymentDetails.currency ?? "<nil>") " +
                "invoice={invoiceNumber=\(invoice.invoiceNumber ?? "<nil>")} " +
                "orderDescription=\(orderDescription ?? "<nil>")"
        )

        guard !customer.isEmpty else { return }
        logger.info("[charge] customer \(customer.redactedFieldSummary)")
    }
}

extension PayabliTTPCustomerData {
    /// Which fields the caller set, never what they hold: each renders
    /// `[REDACTED]` when set and `[nil]` when not.
    ///
    /// `.private` redacts a value in a shared log and still delivers it to a
    /// local stream and to a sysdiagnose, so a cardholder name has no privacy
    /// level it may be logged at. The same holds for the contact and address
    /// fields beside it, which the Android core also emits redacted.
    var redactedFieldSummary: String {
        let fields: [(String, String?)] = [
            ("firstName", firstName),
            ("lastName", lastName),
            ("customerNumber", customerNumber),
            ("customerId", customerId.map(String.init)),
            ("company", company),
            ("email", email),
            ("phone", phone),
            ("billing.address1", billingAddress1),
            ("billing.address2", billingAddress2),
            ("billing.city", billingCity),
            ("billing.state", billingState),
            ("billing.zip", billingZip),
            ("billing.country", billingCountry),
            ("billing.email", billingEmail),
            ("billing.phone", billingPhone),
            ("shipping.address1", shippingAddress1),
            ("shipping.address2", shippingAddress2),
            ("shipping.city", shippingCity),
            ("shipping.state", shippingState),
            ("shipping.zip", shippingZip),
            ("shipping.country", shippingCountry)
        ]
        return fields
            .map { "\($0.0)=\(PayabliLogger.redactFully($0.1))" }
            .joined(separator: " ")
    }
}
