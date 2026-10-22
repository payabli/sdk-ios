import Foundation
import PayabliSDKCore

// MARK: - Charge pipeline

/// Result of a `PATCH /MoneyIn/update/{id}` attempt — typed so the caller
/// sees the failure reason without re-reading logs.
private enum TTPUpdateOutcome {
    case succeeded
    case failed(reason: String, retryAfter: TimeInterval?, processorHasNoRecord: Bool)

    /// The caller cancelled. The best-effort notify after a reader failure ignores it.
    case cancelled
}

@available(iOS 16.7, *)
@MainActor
extension PayabliTTP {
    /// Charges a sale.
    ///
    /// Threads the `paymentDetails` / `customer` / `invoice` / `orderDescription`
    /// snapshot through the 3-step flow:
    ///   1. `POST /MoneyIn/initiate` — backend mints the `paymentTransId`.
    ///   2. `provider.startReading(_:)` — NFC tap. `paymentTransId` wires as
    ///      both `merchantTransactionId` and `merchantOrderId`.
    ///   3. `PATCH /MoneyIn/update/{paymentTransId}` — only the provider
    ///      response travels; everything else was persisted at step 1.
    ///
    /// Every charge opens under a key of its own. One whose outcome is unknown keeps it for four minutes, and only
    /// `attempt: .retry` resends it, describing the same amount, service fee, currency and, when the held charge set
    /// one, invoice number; any other retry is refused with `RETRY_NOT_SAME_PAYMENT` before anything is sent.
    ///
    /// - Parameters:
    ///   - paymentDetails: the amount, service fee and currency to charge.
    ///   - customer: the customer to attach, empty when the caller passes none.
    ///   - invoice: the invoice to attach, whose `invoiceNumber` reaches the read.
    ///   - orderDescription: an order description, trimmed, with a blank one dropped.
    ///   - attempt: `.retry` to repeat the most recent charge whose outcome is unknown; `.newPayment` otherwise.
    /// - Returns: the transaction result, carrying the `paymentTransId` minted at initiate.
    public func charge(
        paymentDetails: PayabliTTPPaymentDetails,
        customer: PayabliTTPCustomerData = PayabliTTPCustomerData(),
        invoice: PayabliTTPInvoiceData = PayabliTTPInvoiceData(),
        orderDescription: String? = nil,
        attempt: PayabliAttempt = .newPayment
    ) async throws -> TransactionResult {
        let progress = ChargeProgress()
        do {
            return try await holdingSessionSetup {
                try await runCharge(
                    paymentDetails: paymentDetails,
                    customer: customer,
                    invoice: invoice,
                    orderDescription: orderDescription,
                    attempt: attempt,
                    progress: progress
                )
            }
        } catch {
            throw TapToPayErrorTranslation.hostError(
                for: error,
                chargeOf: progress.paymentTransId,
                askedForCard: progress.askedForCard,
                resentKey: progress.resentKey
            )
        }
    }

    private func runCharge(
        paymentDetails: PayabliTTPPaymentDetails,
        customer: PayabliTTPCustomerData,
        invoice: PayabliTTPInvoiceData,
        orderDescription: String?,
        attempt: PayabliAttempt,
        progress: ChargeProgress
    ) async throws -> TransactionResult {
        // Called directly: `reinitialize()` would wait on the gate this charge holds. Its own task keeps a
        // cancelled charge from stopping the repair.
        try await Task { @MainActor in try await self.runReinitializeIfNeeded() }.value

        let charge = try enterCharge()
        defer { leaveCharge(charge) }

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

        let deviceId = try chargingDeviceId(for: charge)
        // After the checks, so a charge that never reaches the wire holds no key.
        let reservation = try chargeKeys.reserve(
            entry: entryPoint,
            environment: environment,
            attempt: attempt,
            description: ChargeDescription(paymentDetails: paymentDetails, invoice: invoice)
        )
        progress.resentKey = reservation.reused
        var arrivedAt: ContinuousClock.Instant? = reservation.reservedAt
        defer {
            chargeKeys.supersede(entry: entryPoint, environment: environment, key: reservation.key, arrivedAt: arrivedAt)
        }
        let mark = PayabliSendMark()
        do {
            return try await runOpening(
                context: context,
                deviceId: deviceId,
                reservation: reservation,
                mark: mark,
                charge: charge,
                progress: progress
            )
        } catch {
            if !progress.askedForCard {
                // A 409 extends no marker an earlier send wrote, and a send that never left writes none.
                let unsent = !mark.mayHaveLeft || !(error is CancellationError || Self.leavesOutcomeUnknown(error))
                if progress.paymentTransId == nil, unsent || Self.isConflict(error) {
                    arrivedAt = nil
                }
                // No card was asked for, so no money moved and a fresh key protects no sale.
                settleFresh(reservation)
            }
            throw error
        }
    }

    /// Opens the payment under `reservation`'s key, reads the card and closes the payment.
    ///
    /// - Parameter context: the payment's details, customer, invoice and description, as the caller gave them.
    /// - Parameter deviceId: the device handle the opening's payment method carries.
    /// - Parameter reservation: the key the opening sends, and whether it was already held.
    /// - Parameter mark: set when the opening reaches the HTTP layer.
    /// - Parameter charge: the charge holding the session.
    /// - Parameter progress: how far the charge got, which decides what its failure tells a host.
    /// - Returns: the transaction result, on an approval the close confirmed.
    private func runOpening(
        context: TTPTransactionContext,
        deviceId: String,
        reservation: ChargeKeyStore.Reservation,
        mark: PayabliSendMark,
        charge: Int,
        progress: ChargeProgress
    ) async throws -> TransactionResult {
        // Step 1 — backend mints the paymentTransId.
        let paymentTransId = try await PayabliSendMark.$current.withValue(mark) {
            try await transactionClient.initiate(
                entryPoint: entryPoint,
                deviceId: deviceId,
                idempotencyKey: reservation.key,
                paymentDetails: context.paymentDetails,
                customer: context.customer,
                invoice: context.invoice,
                orderDescription: context.orderDescription
            )
        }
        progress.paymentTransId = paymentTransId

        // Again here, because a replacement can land while the payment opens, and by then the reader may be armed
        // for another merchant.
        if !isLive() {
            try await refuseRetiredCharge(paymentTransId: paymentTransId, charge: charge)
        }

        // Step 2 — NFC tap.
        let readRequest = CardReadRequest(
            amount: context.paymentDetails.amount,
            merchantTransactionId: paymentTransId,
            merchantOrderId: paymentTransId,
            merchantInvoiceNumber: context.invoice.invoiceNumber,
            customer: context.customer,
            invoice: context.invoice
        )
        let readResult: CardReadResult
        let generation = SessionSetupGate.shared.readerGeneration
        // Set before the reader is asked, not after it answers: the processor can take the sale before the
        // answer arrives.
        progress.askedForCard = true
        recordChargeActivity(.waitingForCard, for: charge)
        do {
            readResult = try await provider.startReading(readRequest)
        } catch {
            let failure = readFailure(error, paymentTransId: paymentTransId)

            // Best-effort backend notify so the transaction isn't left dangling.
            // Its outcome does not change what the caller is told.
            recordChargeActivity(.closing, for: charge)
            let close = await tryUpdate(
                paymentTransId: paymentTransId,
                payload: .nfcFailure(description: String(describing: error))
            )
            // A close that lands keeps the key: the tap's answer is unknown. The processor holding no record of the
            // payment is the one answer that says nothing was captured.
            if case .failed(_, _, processorHasNoRecord: true) = close {
                settleFresh(reservation)
            }

            // Expired after the close, so `closing` is published first. Only while the reader that failed is
            // still the current one. The gate keeps every other setup out until the charge returns, so this
            // compares equal unless that guarantee breaks.
            if generation == SessionSetupGate.shared.readerGeneration,
               readerFailureInvalidatesSession(error),
               sessionManager.transition(to: .sessionExpired)
            {
                syncPublished()
            }
            throw failure
        }

        recordChargeActivity(.closing, for: charge)
        return try await runSuccessUpdate(paymentTransId: paymentTransId, readResult: readResult, reservation: reservation)
    }

    /// Releases a key this charge minted, because its charge reached an outcome not in doubt. A resent key names an
    /// earlier charge, so nothing this one learns settles it.
    ///
    /// - Parameter reservation: the key the charge sent, and whether it was already held.
    private func settleFresh(_ reservation: ChargeKeyStore.Reservation) {
        guard !reservation.reused else { return }
        chargeKeys.settle(entry: entryPoint, environment: environment, key: reservation.key)
    }

    /// The text the service refuses a close with when the processor has no record of the payment.
    private static let processorHasNoRecord = "Unable to locate the transaction with the payment processor"

    private static func saysTheProcessorHasNoRecord(_ error: Error) -> Bool {
        guard let refusal = error as? any PayabliError, refusal.type == .validation else { return false }
        return refusal.detail == processorHasNoRecord
    }

    private static func isConflict(_ error: Error) -> Bool {
        (error as? any PayabliError)?.type == .conflict
    }

    private static func leavesOutcomeUnknown(_ error: Error) -> Bool {
        (error as? any PayabliError)?.type.category == .outcomeUnknown
    }

    /// Step 3 — the update, sent whatever the processor answered. Only an approval is a payment, and a
    /// refusal stays a refusal even when the update then fails.
    ///
    /// - Parameter paymentTransId: the transaction the update closes, minted at initiate.
    /// - Parameter readResult: what the reader read, whose outcome decides the capture.
    /// - Parameter reservation: the key the charge sent, settled once the outcome is definite.
    /// - Returns: the transaction's result, on an approval the update confirmed.
    private func runSuccessUpdate(
        paymentTransId: String,
        readResult: CardReadResult,
        reservation: ChargeKeyStore.Reservation
    ) async throws -> TransactionResult {
        let update = await tryUpdate(paymentTransId: paymentTransId, payload: .success(readResult))

        let capture: PayabliTTPCapture
        switch readResult.outcome {
        case .declined:
            settleFresh(reservation)
            throw PayabliTTPError.cardDeclined(paymentTransId: paymentTransId)
        case .approved:
            capture = .charged
        case .indeterminate:
            capture = .unknown
        }

        switch update {
        case .succeeded where capture == .charged:
            settleFresh(reservation)
            return TransactionResult(paymentTransId: paymentTransId)
        case .succeeded:
            throw PayabliTTPError.outcomeUnknown(paymentTransId: paymentTransId)
        case let .failed(reason, retryAfter, _):
            throw PayabliTTPError.updateFailed(
                reason: reason, paymentTransId: paymentTransId, capture: capture, retryAfter: retryAfter
            )
        case .cancelled:
            // The card was read, so a caller who cancelled is still told what the tap did.
            throw PayabliTTPError.updateFailed(
                reason: "The update was cancelled", paymentTransId: paymentTransId, capture: capture
            )
        }
    }

    /// `@objc` companion to `charge(paymentDetails:customer:invoice:orderDescription:attempt:)`.
    ///
    /// On success the completion is invoked with a non-nil
    /// `PayabliTTPTransactionResultObjC` and `nil` error. On failure the
    /// completion receives a nil result and an `NSError`, a ``TapToPayError``
    /// with its catalog number as the code. The completion is always invoked
    /// on the main thread.
    ///
    /// - Parameters:
    ///   - request: the payment details, and the customer, invoice, description and attempt where they are set.
    ///   - completion: the result, or the error the charge failed with.
    @objc public func charge(
        _ request: PayabliTTPChargeRequestObjC,
        completion: @escaping (PayabliTTPTransactionResultObjC?, NSError?) -> Void
    ) {
        let swiftDetails = request.paymentDetails.toSwift()
        let swiftCustomer = request.customer?.toSwift() ?? PayabliTTPCustomerData()
        let swiftInvoice = request.invoice?.toSwift() ?? PayabliTTPInvoiceData()
        let orderDescription = request.orderDescription
        let attempt = request.attempt

        Task { @MainActor in
            do {
                let result = try await self.charge(
                    paymentDetails: swiftDetails,
                    customer: swiftCustomer,
                    invoice: swiftInvoice,
                    orderDescription: orderDescription,
                    attempt: attempt
                )
                completion(PayabliTTPTransactionResultObjC(result), nil)
            } catch {
                completion(nil, error.toPayabliNSError())
            }
        }
    }

    // MARK: - Charge helpers

    /// Holds the reader for a new charge and names it, or throws when the session is not ready.
    ///
    /// - Returns: the charge's name, held until `leaveCharge` releases it.
    /// Ends a charge whose session was replaced while its payment opened: the card is not read, the opened payment's
    /// close is attempted, and the terminal lands `.failed(reason: .sessionEnded)`.
    ///
    /// - Parameter paymentTransId: the payment the charge opened.
    /// - Parameter charge: the charge holding the session.
    /// - Throws: `sessionNotInitialized`, carrying the opened payment and `capture: .notCharged`.
    private func refuseRetiredCharge(paymentTransId: String, charge: Int) async throws -> Never {
        recordChargeActivity(.closing, for: charge)
        _ = await tryUpdate(paymentTransId: paymentTransId, payload: .nfcFailure(description: Self.retiredReason))
        sessionManager.failCharge(.sessionEnded, for: charge)
        syncPublished()
        throw TapToPayError(
            type: .sessionNotInitialized,
            reason: Self.retiredReason,
            detail: nil,
            paymentTransId: paymentTransId,
            capture: .notCharged
        )
    }

    private func enterCharge() throws -> Int {
        guard let charge = sessionManager.beginCharge() else {
            throw PayabliTTPError.notReady(current: sessionState)
        }
        syncPublished()
        return charge
    }

    private func leaveCharge(_ charge: Int) {
        sessionManager.endCharge(charge)
        syncPublished()
    }

    func recordChargeActivity(_ activity: TapToPayChargeActivity, for charge: Int) {
        sessionManager.recordChargeActivity(activity, for: charge)
        syncPublished()
    }

    /// The case the reader raised, with the payment it opened. A failure the reader already classified is
    /// kept, and the charge adds its payment at the edge. Any other failure with no case of its own that can
    /// carry the payment is reported as `nfcFailed`.
    ///
    /// - Parameter error: what the reader threw, before the charge attached its payment.
    /// - Parameter paymentTransId: the payment the failure is attached to, minted at initiate.
    /// - Returns: the failure the caller is told, carrying the payment.
    private func readFailure(_ error: Error, paymentTransId: String) -> Error {
        if let classified = error as? TapToPayError {
            return classified
        }
        switch error as? PayabliTTPError {
        case let .nfcFailed(reason, _):
            return PayabliTTPError.nfcFailed(reason: reason, paymentTransId: paymentTransId)
        case let .readerSetupFailed(reason, _):
            return PayabliTTPError.readerSetupFailed(reason: reason, paymentTransId: paymentTransId)
        case .readerOSVersionNotSupported:
            return PayabliTTPError.readerOSVersionNotSupported(paymentTransId: paymentTransId, capture: .unknown)
        case let .some(ttpError):
            return PayabliTTPError.nfcFailed(reason: ttpError.localizedDescription, paymentTransId: paymentTransId)
        case .none:
            return PayabliTTPError.nfcFailed(reason: String(describing: error), paymentTransId: paymentTransId)
        }
    }

    /// The device the opening charges as. Fails loudly if `deviceId` is missing — otherwise any later
    /// `PATCH /update/{id}` would 400 on a non-existent transaction.
    ///
    /// - Parameter charge: the charge's name, marked failed where `deviceId` is missing.
    /// - Returns: the device handle the opening's payment method carries.
    private func chargingDeviceId(for charge: Int) throws -> String {
        // Read at the point of use: the binding can be replaced between calls, and
        // a copy taken earlier names a device this request cannot sign for.
        guard let deviceId = try attestation.cachedDeviceId(for: entryPoint) else {
            // Lands failed: ending ready would send every retry back to this line.
            sessionManager.failCharge(.deviceSetupRequired, for: charge)
            syncPublished()
            throw TapToPayError(
                type: .deviceSetupRequired,
                reason: "This device has no stored registration; initialize again",
                detail: nil
            )
        }
        return deviceId
    }

    /// Runs `PATCH /update/{paymentTransId}` with retry; bearer auth and 401 refresh-and-retry are
    /// `session.transport`'s. Returns a typed outcome rather than a `Bool`.
    ///
    /// - Parameter paymentTransId: the transaction the update is sent for, minted at initiate.
    /// - Parameter payload: what the reader did, as the success or failure the update carries.
    /// - Returns: what the update ended as: succeeded, failed with its reason and wait, or cancelled.
    private func tryUpdate(
        paymentTransId: String,
        payload: TTPUpdatePayload
    ) async -> TTPUpdateOutcome {
        let body = TTPTransactionClient.updateBody(for: payload)
        let logger = self.logger
        let path = "/api/v2/MoneyIn/update/\(PercentEncoding.segment(paymentTransId))"
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
            // Raise a non-2xx as its mapped error and let the policy classify it. Deciding here would
            // make retryability this call site's opinion, which the next call site is free to differ on.
            try await Retry.run(policy: retryPolicy, logger: logger) { attempt in
                let response = try await performOnce(attempt: String(attempt))
                try mapPayabliHTTPError(response: response)
            }
            return .succeeded
        } catch is CancellationError {
            // Nothing below retries a cancelled request any more. What the caller is told depends on what
            // the tap did.
            return .cancelled
        } catch {
            // The caller still gets this surface's vocabulary, so the outcome reads the same whatever
            // layer underneath produced the failure.
            return .failed(
                reason: error.localizedDescription,
                retryAfter: (error as? PayabliRetryAfter)?.retryAfter,
                processorHasNoRecord: Self.saysTheProcessorHasNoRecord(error)
            )
        }
    }

    /// Two lines: the charge summary, then which customer fields the caller
    /// populated. No customer value is emitted at any privacy level.
    ///
    /// - Parameter paymentDetails: the amounts and currency the summary line logs.
    /// - Parameter customer: the customer whose set fields the second line names.
    /// - Parameter invoice: the invoice whose number the summary line carries.
    /// - Parameter orderDescription: the description, trimmed, with a blank one already dropped.
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
    /// fields beside it.
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
