import Foundation
import PayabliSDKCore

@available(iOS 16.7, *)
@MainActor
public extension PayabliTTP {
    /// Closes the payment named by `paymentTransId`, with no second tap and no second payment.
    ///
    /// A close may be sent again whether or not an earlier one reached the service: it moves no money. Any identifier
    /// a charge returned or failed with can be closed, including one kept from before the app restarted.
    ///
    /// A call made while a charge on this entry point runs waits for that charge, and a charge started while this runs
    /// is refused with `TERMINAL_NOT_READY`. The session state does not change.
    ///
    /// - Parameter paymentTransId: the payment to close, as a charge's result or failure named it.
    /// - Throws: ``TapToPayError``: `PAYMENT_NOT_CLOSED` when the close was not confirmed, carrying the payment and
    ///   whether its card was charged; `PERMISSION_DENIED` when the credentials may not act on that payment, which a
    ///   retry does not change.
    func closeCapturedCharge(paymentTransId: String) async throws {
        // Sent, a dot segment would reach another route.
        guard TTPTransactionClient.isAddressable(paymentTransId) else {
            throw TapToPayError(
                type: .paymentNotClosed,
                reason: "That identifier cannot name one transaction",
                detail: nil,
                paymentTransId: paymentTransId,
                capture: .unknown
            )
        }
        let gate = SessionSetupGate.shared
        let runningCharge = gate.admitClose(entryPoint)
        defer { gate.releaseClose(entryPoint) }
        // The charge on this entry point sends its own close first.
        if let runningCharge {
            _ = try? await runningCharge.value
        }
        try Task.checkCancellation()

        // Its own task, so a caller that cancels does not stop a close already sent.
        let closed = await Task { @MainActor in await self.sendClose(paymentTransId) }.value
        try Task.checkCancellation()
        try closed.get()
    }

    /// Sends the close for a payment this process holds no reader answer for.
    ///
    /// - Parameter paymentTransId: the payment to close.
    /// - Returns: success once the service confirmed the close; otherwise the host's error, with the capture unknown.
    private func sendClose(_ paymentTransId: String) async -> Result<Void, TapToPayError> {
        do {
            try await sendUpdate(paymentTransId: paymentTransId, payload: .noOutcome)
            return .success(())
        } catch {
            // Waiting and sending again cannot change a refusal of the caller.
            let type: PayabliErrorType = (error as? any PayabliError)?.type == .permissionDenied
                ? .permissionDenied
                : .paymentNotClosed
            let answer = TapToPayErrorTranslation.answer(of: error)
            return .failure(TapToPayError(
                type: type,
                reason: type.message,
                detail: nil,
                paymentTransId: paymentTransId,
                capture: .unknown,
                retryAfter: (error as? PayabliRetryAfter)?.retryAfter,
                httpStatus: answer.httpStatus,
                rawCode: answer.rawCode
            ))
        }
    }

    /// `@objc` companion to ``closeCapturedCharge(paymentTransId:)``.
    ///
    /// The completion receives `nil` when the close was confirmed, or an `NSError`, a ``TapToPayError`` with its
    /// catalog number as the code. It is always invoked on the main thread.
    ///
    /// - Parameters:
    ///   - paymentTransId: the payment to close, as a charge's result or failure named it.
    ///   - completion: the error the close failed with, or `nil` when it was confirmed.
    @objc func closeCapturedCharge(
        _ paymentTransId: String,
        completion: @escaping (NSError?) -> Void
    ) {
        Task { @MainActor in
            do {
                try await self.closeCapturedCharge(paymentTransId: paymentTransId)
                completion(nil)
            } catch {
                completion(error.toPayabliNSError())
            }
        }
    }
}
