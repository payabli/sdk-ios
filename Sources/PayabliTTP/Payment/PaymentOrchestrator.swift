import Foundation

/// Orchestrates the charge(.sale) payment flow:
/// 1. POST /initiate  → create transaction in Payabli backend
/// 2. Fiserv NFC tap  → card reader processes the payment
/// 3. PATCH /update    → send Fiserv result back to Payabli
///
/// If step 3 fails, the update is queued in PendingUpdateQueue
/// and retried on next initialization. The partner still gets a
/// TransactionResult with syncStatus = .pendingSyncWithBackend.
final class PaymentOrchestrator {

    private let transactionService: TransactionService
    private let cardReader: CardReading
    private let deviceId: String
    private let pendingQueue: PendingUpdateQueue
    private let events: EventStream
    private let entry: String

    init(
        transactionService: TransactionService,
        cardReader: CardReading,
        deviceId: String,
        pendingQueue: PendingUpdateQueue,
        events: EventStream,
        entry: String
    ) {
        self.transactionService = transactionService
        self.cardReader = cardReader
        self.deviceId = deviceId
        self.pendingQueue = pendingQueue
        self.events = events
        self.entry = entry
    }

    /// Execute a sale: initiate → NFC tap → update.
    func chargeSale(
        amount: Decimal,
        order: OrderDetails?,
        customer: CustomerData?,
        invoice: InvoiceData?,
        serviceFee: Decimal?
    ) async throws -> TransactionResult {

        // Step 1: Initiate transaction in Payabli backend
        let initiateBody = buildInitiateRequest(
            amount: amount,
            order: order,
            customer: customer,
            invoice: invoice,
            serviceFee: serviceFee
        )

        let initiateResponse = try await transactionService.initiateTransaction(body: initiateBody)

        guard let paymentTransId = initiateResponse.paymentTransId else {
            throw PayabliTTPError.backendError(statusCode: 0, message: "Missing paymentTransId in initiate response")
        }

        events.emit(.transactionInitiated(paymentTransId: paymentTransId))

        // Step 2: NFC tap via Fiserv
        events.emit(.waitingForCardTap)

        let cardReaderResponse: [String: Any]
        do {
            cardReaderResponse = try await cardReader.charge(
                amount: amount,
                merchantTransactionId: paymentTransId
            )
        } catch {
            // NFC failed -- report error to backend
            try? await sendUpdateError(
                paymentTransId: paymentTransId,
                error: error
            )
            events.emit(.transactionFailed(error: error.localizedDescription))
            throw PayabliTTPError.fiservError(error.localizedDescription)
        }

        events.emit(.cardTapCompleted)

        // Step 3: Send Fiserv result to Payabli backend
        let syncStatus = await sendUpdateSuccess(
            paymentTransId: paymentTransId,
            fiservResponse: cardReaderResponse
        )

        events.emit(.transactionCompleted(paymentTransId: paymentTransId))

        return TransactionResult(
            transactionId: paymentTransId,
            syncStatus: syncStatus
        )
    }

    /// Retry any pending updates that failed in previous sessions.
    func retryPendingUpdates() async {
        let pending = pendingQueue.all()
        for update in pending {
            guard let dict = update.responseDict else {
                Log.payment.error("Corrupt pending update for \(update.paymentTransId), removing")
                pendingQueue.remove(paymentTransId: update.paymentTransId)
                continue
            }
            do {
                let body = UpdateRequest(fiservResponse: dict, error: nil)
                try await transactionService.updateTransaction(
                    paymentTransId: update.paymentTransId,
                    body: body
                )
                pendingQueue.remove(paymentTransId: update.paymentTransId)
                events.emit(.pendingUpdateSynced(paymentTransId: update.paymentTransId))
            } catch {
                events.emit(.pendingUpdateRetried(paymentTransId: update.paymentTransId))
            }
        }
    }

    // MARK: - Internal

    private func buildInitiateRequest(
        amount: Decimal,
        order: OrderDetails?,
        customer: CustomerData?,
        invoice: InvoiceData?,
        serviceFee: Decimal?
    ) -> InitiateRequest {
        InitiateRequest(
            entry: entry,
            orderId: order?.orderId,
            orderDescription: order?.description,
            paymentDetails: .init(totalAmount: amount, serviceFee: serviceFee),
            paymentMethod: .init(method: "ttp", device: deviceId),
            customerData: customer.map { .init(firstName: $0.firstName, lastName: $0.lastName) },
            invoiceData: invoice.map {
                .init(
                    invoiceNumber: $0.invoiceNumber,
                    items: $0.items.isEmpty ? nil : $0.items.map {
                        .init(name: $0.name, amount: $0.amount, quantity: $0.quantity)
                    }
                )
            }
        )
    }

    /// Send successful Fiserv result to backend with retry. If all attempts fail, queue for later.
    private func sendUpdateSuccess(
        paymentTransId: String,
        fiservResponse: [String: Any]
    ) async -> SyncStatus {
        let body = UpdateRequest(fiservResponse: fiservResponse, error: nil)
        let retry = RetryPolicy(maxAttempts: 3, baseDelay: 1.0, maxDelay: 8.0)
        do {
            try await retry.execute {
                try await transactionService.updateTransaction(
                    paymentTransId: paymentTransId,
                    body: body
                )
            }
            return .synced
        } catch {
            Log.payment.error("Update failed after retries for \(paymentTransId), queuing")
            pendingQueue.enqueue(
                paymentTransId: paymentTransId,
                responseDict: fiservResponse
            )
            events.emit(.pendingUpdateQueued(paymentTransId: paymentTransId))
            return .pendingSyncWithBackend
        }
    }

    /// Best-effort: notify backend that the NFC tap failed.
    private func sendUpdateError(
        paymentTransId: String,
        error: Error
    ) async throws {
        let body = UpdateRequest(
            fiservResponse: nil,
            error: .init(
                title: "NFC Tap Failed",
                description: error.localizedDescription,
                failureReason: String(describing: error)
            )
        )
        try await transactionService.updateTransaction(
            paymentTransId: paymentTransId,
            body: body
        )
    }
}
