import Foundation
import PayabliSDKCore

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Async variants (PRD FR-11J.1 "completion callback OR async return")
//
// These are additive: the callback-based methods above remain unchanged for
// MAUI / React Native / Flutter bridging. Swift `async throws` auto-bridges
// to an `@objc` completion handler, so this surface is still consumable from
// Objective-C. Typed throws are intentionally NOT used (FR-6.6 @objc compat).

@MainActor
extension PayabliPayIn {

    // MARK: - Tokenization

    #if os(iOS)
    /// Presents the tokenization form and awaits the resulting token.
    ///
    /// Auto-dismisses the sheet on completion (success, cancel, or error).
    /// Equivalent to `createTokenizationViewController(...)` + manual
    /// present/dismiss; see PRD FR-6.2 for the callback-based method.
    public func tokenize(
        type: PayabliPaymentType,
        customerId: Int,
        from presenter: UIViewController,
        cardStrings: CardFormStrings = .default,
        achStrings: ACHFormStrings = .default,
        allowedBrands: PayabliCardBrand = .all
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let vc = createTokenizationViewController(
                type: type,
                customerId: customerId,
                cardStrings: cardStrings,
                achStrings: achStrings,
                allowedBrands: allowedBrands
            ) { [weak presenter] token, error in
                presenter?.dismiss(animated: true) {
                    if let token {
                        continuation.resume(returning: token)
                    } else {
                        continuation.resume(
                            throwing: error ?? PayabliGenericError(
                                code: .unknown,
                                reason: "Tokenization returned no result"
                            )
                        )
                    }
                }
            }
            presenter.present(vc, animated: true)
        }
    }
    #endif

    // MARK: - Payment processing (getpaid)

    #if os(iOS)
    /// Presents the payment form and awaits the resulting `PayabliTransactionResult`.
    ///
    /// Throws on decline (`PayabliPaymentError.decline`), validation, server
    /// error, or user cancellation. See PRD FR-12A and FR-12C.
    public func processPayment(
        type: PayabliPaymentType,
        paymentRequest: PayabliPaymentRequest,
        customerId: Int,
        from presenter: UIViewController,
        cardStrings: CardFormStrings = .default,
        achStrings: ACHFormStrings = .default,
        allowedBrands: PayabliCardBrand = .all
    ) async throws -> PayabliTransactionResult {
        try await withCheckedThrowingContinuation { continuation in
            let vc = processPaymentViewController(
                type: type,
                paymentRequest: paymentRequest,
                customerId: customerId,
                cardStrings: cardStrings,
                achStrings: achStrings,
                allowedBrands: allowedBrands
            ) { [weak presenter] result, error in
                presenter?.dismiss(animated: true) {
                    if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(
                            throwing: error ?? PayabliGenericError(
                                code: .unknown,
                                reason: "Payment returned no result"
                            )
                        )
                    }
                }
            }
            presenter.present(vc, animated: true)
        }
    }
    #endif

    /// Headless stored-method charge — no UI presented (PRD FR-6.10, §9.3C).
    ///
    /// Requires `paymentRequest.storedMethodId` to be set.
    public func chargeStoredMethod(
        methodType: PayabliPaymentType,
        paymentRequest: PayabliPaymentRequest,
        customerId: Int
    ) async throws -> PayabliTransactionResult {
        guard let config, let getpaid else {
            throw PayabliGenericError(
                code: .invalidConfiguration,
                reason: "PayabliPayIn not configured"
            )
        }
        return try await getpaid.chargeStoredMethod(
            methodType: methodType,
            request: paymentRequest,
            customerId: customerId,
            entryPoint: config.entryPoint
        )
    }

    // MARK: - Apple Pay

    #if canImport(PassKit) && os(iOS)
    /// Apple Pay "Set Up" — tokenizes the selected card for later reuse.
    ///
    /// See PRD FR-10.9, §9.3.
    public func setupApplePay(
        applePayConfig: PayabliApplePayConfig,
        amount: Decimal,
        customerId: Int
    ) async throws -> String {
        guard let config, let tokenStorage, let applePayManager else {
            throw PayabliGenericError(
                code: .invalidConfiguration,
                reason: "PayabliPayIn not configured"
            )
        }
        let request = PayabliPaymentRequest(totalAmount: amount)
        let token = try await applePayManager.presentPaymentSheet(
            request: request,
            config: applePayConfig
        )
        let tokenizationRequest = ApplePayTokenizationRequest(
            customerData: CustomerDataBlock(customerId: customerId),
            entryPoint: config.entryPoint,
            paymentMethod: ApplePayTokenizationPayload(
                applePayToken: token.paymentData.base64EncodedString(),
                applePayNetwork: token.network,
                applePayDisplayName: token.displayName
            )
        )
        return try await tokenStorage.tokenizeApplePay(tokenizationRequest)
    }

    /// Apple Pay "Pay" — authorize-and-capture via getpaid.
    ///
    /// See PRD FR-10.9, §9.3.
    public func chargeApplePay(
        applePayConfig: PayabliApplePayConfig,
        paymentRequest: PayabliPaymentRequest,
        customerId: Int
    ) async throws -> PayabliTransactionResult {
        guard let config, let getpaid, let applePayManager else {
            throw PayabliGenericError(
                code: .invalidConfiguration,
                reason: "PayabliPayIn not configured"
            )
        }
        let token = try await applePayManager.presentPaymentSheet(
            request: paymentRequest,
            config: applePayConfig
        )
        return try await getpaid.chargeApplePay(
            token: token,
            request: paymentRequest,
            customerId: customerId,
            entryPoint: config.entryPoint
        )
    }
    #endif
}
