import Foundation
import PayabliSDKCore

// MARK: - Charge pipeline

/// Result of a `PATCH /MoneyIn/update/{id}` attempt — typed so the caller
/// sees the failure reason without re-reading logs.
private enum TTPUpdateOutcome {
    case succeeded
    case failed(reason: String, retryAfter: TimeInterval?, processorHasNoRecord: Bool, httpStatus: Int?, rawCode: String?)

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
    /// `attempt: .retry` resends it, describing the same amount, service fee, currency and any invoice number it set.
    /// A retry refused before anything is sent says why: `RETRY_NOT_SAME_PAYMENT`, `PAYMENT_REFERENCE_OPEN` or
    /// `TERMINAL_NOT_READY`.
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
        let sale = ChargeDescription(paymentDetails: paymentDetails, invoice: invoice)
        do {
            return try await holdingSessionSetup(attempt: attempt, sale: sale) {
                do {
                    return try await runCharge(
                        paymentDetails: paymentDetails,
                        customer: customer,
                        invoice: invoice,
                        orderDescription: orderDescription,
                        attempt: attempt,
                        sale: sale,
                        progress: progress
                    )
                } catch {
                    // A retry refused before its key was reserved still describes the held sale, whose outcome is
                    // unknown. Asked while the gate is held, so no other charge can settle that key under the read.
                    if attempt == .retry, !progress.reserved {
                        progress.retriesHeldSale = chargeKeys.holdsRetryOf(
                            entry: entryPoint,
                            environment: environment,
                            description: sale
                        )
                    }
                    throw error
                }
            }
        } catch {
            throw TapToPayErrorTranslation.hostError(
                for: error,
                chargeOf: progress.paymentTransId,
                askedForCard: progress.askedForCard,
                resentKey: progress.resentKey,
                retriesHeldSale: progress.retriesHeldSale
            )
        }
    }

    private func runCharge(
        paymentDetails: PayabliTTPPaymentDetails,
        customer: PayabliTTPCustomerData,
        invoice: PayabliTTPInvoiceData,
        orderDescription: String?,
        attempt: PayabliAttempt,
        sale: ChargeDescription,
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
            description: sale
        )
        progress.reserved = true
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
                // A refused key extends no marker an earlier send wrote, and a send that never left writes none. Any
                // other answer means the service saw the key.
                if progress.paymentTransId == nil, !mark.mayHaveLeft || error is ChargeKeyRefusal {
                    arrivedAt = nil
                }
                // No card was asked for, so no money moved and a fresh key protects no sale.
                settleFresh(reservation)
                // A paypoint the service refuses card-present for stays refused, so the session says so rather
                // than arming a reader for every later charge to refuse again.
                if case PayabliTTPError.cardPresentNotEnabled = error {
                    markError(error)
                    syncPublished()
                }
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
        opened(paymentTransId, progress: progress)

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
            let touchedNoCard = Self.touchedNoCard(failure)

            // Best-effort backend notify so the transaction isn't left dangling.
            // Its outcome does not change what the caller is told.
            recordChargeActivity(.closing, for: charge)
            let description = String(describing: error)
            let close = await tryUpdate(capture: Self.readCapture(failure, paymentTransId, reservation)) { [transactionClient] in
                try await transactionClient.updateAfterFailedRead(paymentTransId: paymentTransId, description: description)
            }
            // A close that lands keeps the key: the tap's answer is unknown. The processor holding no record of the
            // payment says nothing was captured, and so does a read that never reached a card, whatever the close
            // answers.
            if case .failed(_, _, processorHasNoRecord: true, _, _) = close {
                settleFresh(reservation)
                if touchedNoCard {
                    logger.info("[charge] the close found no record of a payment whose read never reached a card")
                }
            } else if touchedNoCard {
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
            // The no-record close says this charge took nothing, so it replaces the read's failure — but only
            // where this run minted the key: a resent key names an earlier charge, which it cannot settle. A read
            // that never reached a card keeps its 3017, which already says nothing was taken.
            if case let .failed(_, _, processorHasNoRecord: true, httpStatus, rawCode) = close, !reservation.reused,
               !touchedNoCard
            {
                throw PayabliTTPError.paymentNotTaken(paymentTransId: paymentTransId, httpStatus: httpStatus, rawCode: rawCode)
            }
            throw failure
        }

        recordChargeActivity(.closing, for: charge)
        return try await runSuccessUpdate(paymentTransId: paymentTransId, readResult: readResult, reservation: reservation)
    }

    /// Records the payment this charge opened. Only the newest payment on an entry point can be closed from what is
    /// held, so whatever was held there is dropped.
    ///
    /// - Parameter paymentTransId: the payment the opening minted.
    /// - Parameter progress: how far the charge got.
    private func opened(_ paymentTransId: String, progress: ChargeProgress) {
        progress.paymentTransId = paymentTransId
        heldPayments.dropAny(entry: entryPoint, environment: environment)
    }

    /// Releases a key this charge minted, because its charge reached an outcome not in doubt. A resent key names an
    /// earlier charge, so nothing this one learns settles it.
    ///
    /// - Parameter reservation: the key the charge sent, and whether it was already held.
    private func settleFresh(_ reservation: ChargeKeyStore.Reservation) {
        guard !reservation.reused else { return }
        chargeKeys.settle(entry: entryPoint, environment: environment, key: reservation.key)
    }

    /// What the host is told about the money when the close after a failed read fails.
    ///
    /// - Parameter failure: the read's failure.
    /// - Parameter paymentTransId: the payment the charge opened.
    /// - Parameter reservation: the key the charge sent, and whether it was already held.
    /// - Returns: a function of whether the close's refusal says the processor holds no record of the payment. It
    ///   answers not charged for that refusal under a key this charge minted, and otherwise the read failure's capture.
    private static func readCapture(
        _ failure: Error,
        _ paymentTransId: String,
        _ reservation: ChargeKeyStore.Reservation
    ) -> (_ processorHasNoRecord: Bool) -> PayabliTTPCapture {
        { processorHasNoRecord in
            if processorHasNoRecord, !reservation.reused {
                return .notCharged
            }
            let told = TapToPayErrorTranslation.hostError(
                for: failure,
                chargeOf: paymentTransId,
                askedForCard: true,
                resentKey: reservation.reused
            )
            return (told as? TapToPayError)?.capture ?? .unknown
        }
    }

    /// Whether a read failed before the reader reached a card, so the charge took nothing.
    ///
    /// - Parameter failure: the read's failure, as the caller is told it.
    /// - Returns: `true` where the reader session was gone before the read began.
    private static func touchedNoCard(_ failure: Error) -> Bool {
        guard case PayabliTTPError.readerSessionExpired(_, .notCharged) = failure else { return false }
        return true
    }

    private static let processorHasNoRecord = "Unable to locate the transaction with the payment processor"

    /// - Parameter error: what a close failed with.
    /// - Returns: whether it is the service's refusal saying the processor holds no record of the payment.
    static func saysTheProcessorHasNoRecord(_ error: Error) -> Bool {
        guard let refusal = error as? any PayabliError, refusal.type == .validation else { return false }
        return refusal.detail == processorHasNoRecord
    }

    /// Step 3 — the update, sent whatever the processor answered, with the payment held until it lands. Only an
    /// approval is a payment, and a refusal stays a refusal even when the update then fails.
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
        let payment = HeldPayment(
            paymentTransId: paymentTransId,
            outcome: readResult.outcome,
            key: reservation.key,
            resentKey: reservation.reused
        )
        heldPayments.hold(payment, entry: entryPoint, environment: environment)
        let update = await tryUpdate(capture: { _ in payment.capture }) { [transactionClient] in
            try await transactionClient.update(paymentTransId: paymentTransId, result: readResult)
        }
        if case .succeeded = update {
            heldPayments.drop(paymentTransId, entry: entryPoint, environment: environment)
        }

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
        case let .failed(reason, retryAfter, _, httpStatus, rawCode):
            throw PayabliTTPError.updateFailed(
                reason: reason,
                paymentTransId: paymentTransId,
                capture: capture,
                retryAfter: retryAfter,
                httpStatus: httpStatus,
                rawCode: rawCode
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
    /// A `currency` or `attempt` that names no case completes with `VALIDATION_ERROR` before anything is sent.
    ///
    /// - Parameters:
    ///   - request: the payment details, and the customer, invoice, description and attempt where they are set.
    ///   - completion: the result, or the error the charge failed with.
    @objc public func charge(
        _ request: PayabliTTPChargeRequestObjC,
        completion: @escaping (PayabliTTPTransactionResultObjC?, NSError?) -> Void
    ) {
        let swiftDetails: PayabliTTPPaymentDetails
        let attempt: PayabliAttempt
        do {
            swiftDetails = try request.paymentDetails.toSwift()
            attempt = try request.validatedAttempt()
        } catch {
            Task { @MainActor in completion(nil, error.toPayabliNSError()) }
            return
        }
        let swiftCustomer = request.customer?.toSwift() ?? PayabliTTPCustomerData()
        let swiftInvoice = request.invoice?.toSwift() ?? PayabliTTPInvoiceData()
        let orderDescription = request.orderDescription

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
        let reason = Self.retiredReason
        _ = await tryUpdate(capture: { _ in .notCharged }) { [transactionClient] in
            try await transactionClient.updateAfterFailedRead(paymentTransId: paymentTransId, description: reason)
        }
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
        case let .guardFailed(reason, _):
            return PayabliTTPError.guardFailed(reason: reason, paymentTransId: paymentTransId)
        case .readerOSVersionNotSupported:
            return PayabliTTPError.readerOSVersionNotSupported(paymentTransId: paymentTransId, capture: .unknown)
        case let .readerDeviceRefused(reason, _, _):
            return PayabliTTPError.readerDeviceRefused(reason: reason, paymentTransId: paymentTransId, capture: .unknown)
        case let .readerUnavailable(reason, _, _):
            return PayabliTTPError.readerUnavailable(reason: reason, paymentTransId: paymentTransId, capture: .unknown)
        case let .readerSessionExpired(_, capture):
            return PayabliTTPError.readerSessionExpired(paymentTransId: paymentTransId, capture: capture)
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

    /// Runs one of the charge's closes, reports it, and returns how it ended.
    ///
    /// - Parameter capture: what the host is told about the money if the close fails, given whether the refusal says
    ///   the processor holds no record of the payment.
    /// - Parameter send: the close to run.
    /// - Returns: what the update ended as: succeeded, failed with its reason and wait, or cancelled.
    private func tryUpdate(
        capture: (_ processorHasNoRecord: Bool) -> PayabliTTPCapture,
        _ send: @Sendable () async throws -> Void
    ) async -> TTPUpdateOutcome {
        let clock = ContinuousClock()
        let start = clock.now
        reports.closeStarted(.charge)
        do {
            try await send()
            reports.closeSucceeded(.charge, after: clock.now - start)
            return .succeeded
        } catch is CancellationError {
            // A cancelled close is not retried and reports no outcome. What the caller is told depends on what the tap did.
            return .cancelled
        } catch {
            let processorHasNoRecord = Self.saysTheProcessorHasNoRecord(error)
            reports.closeFailed(
                error,
                origin: .charge,
                capture: capture(processorHasNoRecord),
                processorHasNoRecord: processorHasNoRecord,
                type: .paymentNotClosed,
                after: clock.now - start
            )
            return Self.outcome(of: error, processorHasNoRecord: processorHasNoRecord)
        }
    }

    /// - Parameter error: what a close failed with.
    /// - Parameter processorHasNoRecord: whether the refusal says the processor holds no record of the payment.
    /// - Returns: the close's failure, with its reason, wait and answer.
    private static func outcome(of error: Error, processorHasNoRecord: Bool) -> TTPUpdateOutcome {
        // The caller still gets this surface's vocabulary, so the outcome reads the same whatever
        // layer underneath produced the failure.
        let answer = TapToPayErrorTranslation.answer(of: error)
        return .failed(
            reason: error.localizedDescription,
            retryAfter: (error as? PayabliRetryAfter)?.retryAfter,
            processorHasNoRecord: processorHasNoRecord,
            httpStatus: answer.httpStatus,
            rawCode: answer.rawCode
        )
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
                "currency=\(paymentDetails.currency.asSent.code) " +
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
