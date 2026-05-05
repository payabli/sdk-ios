import Foundation
import PayabliSDKCore

#if canImport(PassKit)
import PassKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// Abstraction over PassKit for testability.
///
/// Production uses `RealApplePayManager` which wraps `PKPaymentAuthorizationController`.
/// Tests inject a mock that returns a canned `ApplePayToken` or a cancellation.
@MainActor
public protocol ApplePayManager: AnyObject {
    /// Whether Apple Pay is available on this device (PRD FR-10.8).
    static func canMakePayments() -> Bool

    /// Presents the payment sheet and returns the payment token or an error
    /// (PRD FR-10.1, FR-10.7).
    func presentPaymentSheet(
        request: PayabliPaymentRequest,
        config: PayabliApplePayConfig
    ) async throws -> ApplePayToken
}

#if canImport(PassKit) && os(iOS)
/// Production Apple Pay manager backed by `PKPaymentAuthorizationController`.
@MainActor
public final class RealApplePayManager: NSObject, ApplePayManager {

    public static func canMakePayments() -> Bool {
        PKPaymentAuthorizationController.canMakePayments()
    }

    public func presentPaymentSheet(
        request: PayabliPaymentRequest,
        config: PayabliApplePayConfig
    ) async throws -> ApplePayToken {
        guard Self.canMakePayments() else {
            throw PayabliGenericError(
                code: .invalidConfiguration,
                reason: "Apple Pay is not available on this device"
            )
        }

        let paymentRequest = PKPaymentRequest()
        paymentRequest.merchantIdentifier = config.merchantIdentifier
        paymentRequest.supportedNetworks = config.supportedNetworks
        paymentRequest.merchantCapabilities = config.merchantCapabilities
        paymentRequest.countryCode = config.countryCode
        paymentRequest.currencyCode = config.currencyCode
        paymentRequest.paymentSummaryItems = [
            PKPaymentSummaryItem(
                label: config.merchantName,
                amount: NSDecimalNumber(decimal: request.totalAmount)
            )
        ]

        return try await withCheckedThrowingContinuation { [self] continuation in
            let controller = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
            let delegate = ApplePayDelegate(continuation: continuation)
            controller.delegate = delegate
            self.activeDelegate = delegate // retain
            controller.present { presented in
                if !presented {
                    continuation.resume(throwing: PayabliGenericError(
                        code: .invalidConfiguration,
                        reason: "Failed to present Apple Pay sheet"
                    ))
                    self.activeDelegate = nil
                }
            }
        }
    }

    private var activeDelegate: ApplePayDelegate?
}

/// PKPaymentAuthorizationControllerDelegate bridge that converts the delegate
/// callbacks into a continuation result.
@MainActor
private final class ApplePayDelegate: NSObject, PKPaymentAuthorizationControllerDelegate {

    private var continuation: CheckedContinuation<ApplePayToken, Error>?

    init(continuation: CheckedContinuation<ApplePayToken, Error>) {
        self.continuation = continuation
        super.init()
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        let token = ApplePayToken(
            paymentData: payment.token.paymentData,
            network: payment.token.paymentMethod.network?.rawValue,
            displayName: payment.token.paymentMethod.displayName
        )
        completion(.init(status: .success, errors: nil))
        continuation?.resume(returning: token)
        continuation = nil
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { [weak self] in
            // If the sheet dismissed without authorization, report cancellation.
            guard let self, let cont = self.continuation else { return }
            cont.resume(throwing: PayabliGenericError(
                code: .userCancelled,
                reason: "User cancelled Apple Pay"
            ))
            self.continuation = nil
        }
    }
}
#endif
