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
        throw TapToPayError(
            type: .paymentNotClosed,
            reason: PayabliErrorType.paymentNotClosed.message,
            detail: nil,
            paymentTransId: paymentTransId,
            capture: .unknown
        )
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
