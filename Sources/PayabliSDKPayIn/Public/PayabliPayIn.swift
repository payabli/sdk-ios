import Foundation
import SwiftUI
import PayabliSDKCore

#if canImport(UIKit)
import UIKit
#endif

/// Public callback for tokenization flows.
/// See PRD FR-6.5.
public typealias PayabliTokenizationCompletion = @Sendable @MainActor (String?, Error?) -> Void

/// Public callback for payment-processing flows.
/// See PRD FR-6.9.
public typealias PayabliPaymentCompletion = @Sendable @MainActor (PayabliTransactionResult?, Error?) -> Void

/// The PayIn component facade.
///
/// Singleton entry point for tokenization, card-not-present payments (getpaid),
/// and card-present Tap to Pay. See PRD §5.3 FR-6.
///
/// ```swift
/// let config = PayabliConfig(
///     clientId: "...",
///     clientSecret: "...",
///     entryPoint: "myEntry",
///     environment: .sandbox
/// )
/// PayabliPayIn.shared.configure(config: config, theme: .default)
/// let vc = PayabliPayIn.shared.createTokenizationViewController(type: .card, customerId: 4440) {
///     token, err in
///     // handle result
/// }
/// present(vc, animated: true)
/// ```
@MainActor
public final class PayabliPayIn: NSObject, PayabliComponent {

    // MARK: - PayabliComponent

    public nonisolated static var componentId: String { "payin" }
    public nonisolated static var sessionTier: PayabliSessionTier { .tier1Transactional }
    public nonisolated static var requiredPermissions: [String] {
        ["tokenize_card", "tokenize_ach", "process_payment"]
    }

    // MARK: - Singleton

    public static let shared = PayabliPayIn()

    override private init() {
        super.init()
    }

    // MARK: - State
    //
    // `internal` (not `private`) so the companion `+Async` / `+Forms`
    // extensions in this module can read them without detours.

    var config: PayabliConfig?
    var theme: PayabliTheme = .default
    var auth: PayabliAuth?
    var service: PayabliService?
    var tokenStorage: TokenStorageClient?
    var getpaid: GetpaidClient?
    #if canImport(PassKit) && os(iOS)
    var applePayManager: ApplePayManager?
    #endif

    // MARK: - Public API

    /// Configure the component. Must be called before any operation.
    ///
    /// Performs session-tier validation (PRD §28.7): if the session doesn't
    /// meet this component's required tier, the failure is logged but the
    /// configure call still completes — callers surface the issue on first
    /// operation. Tier enforcement strengthens in v2.0 (§16.7).
    public func configure(config: PayabliConfig, theme: PayabliTheme) {
        do {
            try SessionTierValidator.validate(component: Self.self, against: config)
        } catch {
            PayabliLogger(category: .core).error("Session tier validation failed")
        }
        self.config = config
        self.theme = theme

        let service = PayabliService(environment: config.environment)
        let auth = PayabliAuth(config: config)

        self.service = service
        self.auth = auth
        self.tokenStorage = TokenStorageClient(service: service, auth: auth)
        self.getpaid = GetpaidClient(service: service, auth: auth)
        #if canImport(PassKit) && os(iOS)
        self.applePayManager = RealApplePayManager()
        #endif
    }

    #if canImport(PassKit) && os(iOS)
    /// Override the Apple Pay manager (testing hook).
    public func overrideApplePayManager(_ manager: ApplePayManager) {
        self.applePayManager = manager
    }
    #endif

    #if os(iOS)
    /// Creates a `UIViewController` hosting the tokenization form for the given
    /// payment type. Present modally from the host app.
    ///
    /// `cardStrings`, `achStrings`, and `allowedBrands` are forwarded to the
    /// underlying `CardFormView` / `ACHFormView` for label and brand
    /// customization. Defaults match the unconfigured English path.
    ///
    /// See PRD FR-6.2, FR-3.1.
    public func createTokenizationViewController(
        type: PayabliPaymentType,
        customerId: Int,
        cardStrings: CardFormStrings = .default,
        achStrings: ACHFormStrings = .default,
        allowedBrands: PayabliCardBrand = .all,
        completion: @escaping PayabliTokenizationCompletion
    ) -> UIViewController {
        let rootView = tokenizationRootView(
            type: type,
            customerId: customerId,
            cardStrings: cardStrings,
            achStrings: achStrings,
            allowedBrands: allowedBrands,
            completion: completion
        )
        let hosting = UIHostingController(rootView: rootView)
        hosting.modalPresentationStyle = .formSheet
        hosting.isModalInPresentation = false
        return hosting
    }

    /// Creates a `UIViewController` hosting the payment form that, on submit,
    /// executes an authorize-and-capture via `POST /api/v2/MoneyIn/getpaid`.
    ///
    /// See PRD FR-6.7, FR-12A.
    public func processPaymentViewController(
        type: PayabliPaymentType,
        paymentRequest: PayabliPaymentRequest,
        customerId: Int,
        cardStrings: CardFormStrings = .default,
        achStrings: ACHFormStrings = .default,
        allowedBrands: PayabliCardBrand = .all,
        completion: @escaping PayabliPaymentCompletion
    ) -> UIViewController {
        let rootView = paymentRootView(
            type: type,
            paymentRequest: paymentRequest,
            customerId: customerId,
            cardStrings: cardStrings,
            achStrings: achStrings,
            allowedBrands: allowedBrands,
            completion: completion
        )
        let hosting = UIHostingController(rootView: rootView)
        hosting.modalPresentationStyle = .formSheet
        hosting.isModalInPresentation = false
        return hosting
    }

    // MARK: - UIKit rootView builders
    //
    // Both card and ACH paths wrap the corresponding turn-key SwiftUI view
    // (`CardFormView` / `ACHFormView`) — each owns its own VM and calls the
    // right endpoint internally. `applePay` and `tapToPay` surface a message
    // pointing callers at their dedicated APIs (`setupApplePay` /
    // `chargeApplePay` for Apple Pay, the `PayabliSDKTapToPay` module for
    // Tap to Pay on iPhone).

    @ViewBuilder
    private func tokenizationRootView(
        type: PayabliPaymentType,
        customerId: Int,
        cardStrings: CardFormStrings,
        achStrings: ACHFormStrings,
        allowedBrands: PayabliCardBrand,
        completion: @escaping PayabliTokenizationCompletion
    ) -> some View {
        switch type {
        case .card:
            sheetChrome(title: cardStrings.sheetTitle, cancel: {
                completion(nil, PayabliGenericError(code: .userCancelled, reason: "User cancelled"))
            }) {
                CardFormView(
                    customerId: customerId,
                    theme: theme,
                    strings: cardStrings,
                    allowedBrands: allowedBrands,
                    onCompletion: completion
                )
            }
        case .ach:
            sheetChrome(title: achStrings.sheetTitle, cancel: {
                completion(nil, PayabliGenericError(code: .userCancelled, reason: "User cancelled"))
            }) {
                ACHFormView(
                    customerId: customerId,
                    theme: theme,
                    strings: achStrings,
                    onCompletion: completion
                )
            }
        case .applePay:
            placeholderSheet(title: "Apple Pay",
                             message: "Apple Pay uses setupApplePay / chargeApplePay instead.",
                             onCancel: {
                                 completion(nil, PayabliGenericError(code: .userCancelled, reason: "User cancelled"))
                             })
        case .tapToPay:
            placeholderSheet(title: "Tap to Pay",
                             message: "Tap to Pay lives in PayabliSDKTapToPay — import PayabliSDKTapToPay and use PayabliTTP.",
                             onCancel: {
                                 completion(nil, PayabliGenericError(code: .userCancelled, reason: "User cancelled"))
                             })
        }
    }

    @ViewBuilder
    private func paymentRootView(
        type: PayabliPaymentType,
        paymentRequest: PayabliPaymentRequest,
        customerId: Int,
        cardStrings: CardFormStrings,
        achStrings: ACHFormStrings,
        allowedBrands: PayabliCardBrand,
        completion: @escaping PayabliPaymentCompletion
    ) -> some View {
        switch type {
        case .card:
            sheetChrome(title: cardStrings.sheetTitle, cancel: {
                completion(nil, PayabliGenericError(code: .userCancelled, reason: "User cancelled"))
            }) {
                CardFormView(
                    paymentRequest: paymentRequest,
                    customerId: customerId,
                    theme: theme,
                    strings: cardStrings,
                    allowedBrands: allowedBrands,
                    onCompletion: completion
                )
            }
        case .ach:
            sheetChrome(title: achStrings.sheetTitle, cancel: {
                completion(nil, PayabliGenericError(code: .userCancelled, reason: "User cancelled"))
            }) {
                ACHFormView(
                    paymentRequest: paymentRequest,
                    customerId: customerId,
                    theme: theme,
                    strings: achStrings,
                    onCompletion: completion
                )
            }
        case .applePay:
            placeholderSheet(title: "Apple Pay",
                             message: "Apple Pay uses setupApplePay / chargeApplePay instead.",
                             onCancel: {
                                 completion(nil, PayabliGenericError(code: .userCancelled, reason: "User cancelled"))
                             })
        case .tapToPay:
            placeholderSheet(title: "Tap to Pay",
                             message: "Tap to Pay lives in PayabliSDKTapToPay — import PayabliSDKTapToPay and use PayabliTTP.",
                             onCancel: {
                                 completion(nil, PayabliGenericError(code: .userCancelled, reason: "User cancelled"))
                             })
        }
    }

    @ViewBuilder
    private func sheetChrome<Body: View>(
        title: String,
        cancel: @escaping () -> Void,
        @ViewBuilder body: () -> Body
    ) -> some View {
        VStack(spacing: 0) {
            PayabliSheetHeader(title: title, tint: theme.primaryColor, onCancel: cancel)
            Divider()
            body()
        }
    }

    @ViewBuilder
    private func placeholderSheet(
        title: String,
        message: String,
        onCancel: @escaping () -> Void
    ) -> some View {
        sheetChrome(title: title, cancel: onCancel) {
            VStack {
                Spacer()
                Text(message).foregroundColor(.secondary).padding()
                Spacer()
            }
        }
    }

    public func createPaymentViewController(
        type: PayabliPaymentType,
        paymentRequest: PayabliPaymentRequest,
        customerId: Int,
        cardStrings: CardFormStrings = .default,
        achStrings: ACHFormStrings = .default,
        allowedBrands: PayabliCardBrand = .all,
        completion: @escaping PayabliPaymentCompletion
    ) -> UIViewController {
        processPaymentViewController(
            type: type,
            paymentRequest: paymentRequest,
            customerId: customerId,
            cardStrings: cardStrings,
            achStrings: achStrings,
            allowedBrands: allowedBrands,
            completion: completion
        )
    }
    #endif

    #if canImport(PassKit) && os(iOS)
    /// Present Apple Pay in "Set Up" mode — tokenizes the selected card for
    /// future use via `POST /api/TokenStorage/add` with `method:"applepay"`.
    ///
    /// See PRD FR-10.9, §9.3.
    public func setupApplePay(
        applePayConfig: PayabliApplePayConfig,
        amount: Decimal,
        customerId: Int,
        completion: @escaping PayabliTokenizationCompletion
    ) async {
        guard let config, let tokenStorage, let applePayManager else {
            completion(nil, PayabliGenericError(
                code: .invalidConfiguration,
                reason: "PayabliPayIn not configured"
            ))
            return
        }

        let request = PayabliPaymentRequest(totalAmount: amount)
        do {
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
            let payabliToken = try await tokenStorage.tokenizeApplePay(tokenizationRequest)
            completion(payabliToken, nil)
        } catch {
            completion(nil, error)
        }
    }

    /// Present Apple Pay in "Pay" mode — executes an authorize-and-capture via
    /// `POST /api/v2/MoneyIn/getpaid`.
    ///
    /// See PRD FR-10.9, §9.3.
    public func chargeApplePay(
        applePayConfig: PayabliApplePayConfig,
        paymentRequest: PayabliPaymentRequest,
        customerId: Int,
        completion: @escaping PayabliPaymentCompletion
    ) async {
        guard let config, let getpaid, let applePayManager else {
            completion(nil, PayabliGenericError(
                code: .invalidConfiguration,
                reason: "PayabliPayIn not configured"
            ))
            return
        }

        do {
            let token = try await applePayManager.presentPaymentSheet(
                request: paymentRequest,
                config: applePayConfig
            )
            let result = try await getpaid.chargeApplePay(
                token: token,
                request: paymentRequest,
                customerId: customerId,
                entryPoint: config.entryPoint
            )
            completion(result, nil)
        } catch {
            completion(nil, error)
        }
    }
    #endif

    /// Charges a previously tokenized payment method headlessly (no UI).
    ///
    /// Requires `paymentRequest.storedMethodId` to be set. See PRD FR-6.10, §9.3C.
    public func chargeStoredMethod(
        methodType: PayabliPaymentType,
        paymentRequest: PayabliPaymentRequest,
        customerId: Int,
        completion: @escaping PayabliPaymentCompletion
    ) async {
        guard let config, let getpaid else {
            completion(nil, PayabliGenericError(
                code: .invalidConfiguration,
                reason: "PayabliPayIn not configured"
            ))
            return
        }

        do {
            let result = try await getpaid.chargeStoredMethod(
                methodType: methodType,
                request: paymentRequest,
                customerId: customerId,
                entryPoint: config.entryPoint
            )
            completion(result, nil)
        } catch {
            completion(nil, error)
        }
    }

    // MARK: - Internal (also exposed for tests)

    func submitCardTokenization(
        _ viewModel: CardFormViewModel,
        customerId: Int,
        completion: @escaping PayabliTokenizationCompletion
    ) async {
        guard viewModel.isValid else {
            viewModel.endSubmission(error: Self.preflightError)
            return
        }
        guard let config, let tokenStorage else {
            let error = Self.notConfiguredError
            viewModel.endSubmission(error: error)
            completion(nil, error)
            return
        }

        viewModel.beginSubmission()
        let request = CardTokenizationRequest(
            customerData: CustomerDataBlock(customerId: customerId),
            entryPoint: config.entryPoint,
            paymentMethod: viewModel.makePayload()
        )

        do {
            let token = try await tokenStorage.tokenizeCard(request)
            viewModel.endSubmission()
            completion(token, nil)
        } catch {
            viewModel.endSubmission(error: error)
            completion(nil, error)
        }
    }

    func submitACHTokenization(
        _ viewModel: ACHFormViewModel,
        customerId: Int,
        completion: @escaping PayabliTokenizationCompletion
    ) async {
        guard viewModel.isValid else {
            viewModel.endSubmission(error: Self.preflightError)
            return
        }
        guard let config, let tokenStorage else {
            let error = Self.notConfiguredError
            viewModel.endSubmission(error: error)
            completion(nil, error)
            return
        }

        viewModel.beginSubmission()
        let request = ACHTokenizationRequest(
            customerData: CustomerDataBlock(customerId: customerId),
            entryPoint: config.entryPoint,
            paymentMethod: viewModel.makePayload()
        )

        do {
            let token = try await tokenStorage.tokenizeACH(request)
            viewModel.endSubmission()
            completion(token, nil)
        } catch {
            viewModel.endSubmission(error: error)
            completion(nil, error)
        }
    }

    private static let preflightError = PayabliGenericError(
        code: .invalidConfiguration,
        reason: "Please correct the errors and try again."
    )

    private static let notConfiguredError = PayabliGenericError(
        code: .invalidConfiguration,
        reason: "PayabliPayIn not configured"
    )

    // MARK: - Payment submit handlers

    func submitCardPayment(
        _ viewModel: CardFormViewModel,
        request: PayabliPaymentRequest,
        customerId: Int,
        completion: @escaping PayabliPaymentCompletion
    ) async {
        guard viewModel.isValid else {
            viewModel.endSubmission(error: Self.preflightError)
            return
        }
        guard let config, let getpaid else {
            let error = Self.notConfiguredError
            viewModel.endSubmission(error: error)
            completion(nil, error)
            return
        }

        viewModel.beginSubmission()
        do {
            let result = try await getpaid.chargeCard(
                payload: viewModel.makePayload(),
                request: request,
                customerId: customerId,
                entryPoint: config.entryPoint
            )
            viewModel.endSubmission()
            completion(result, nil)
        } catch {
            viewModel.endSubmission(error: error)
            completion(nil, error)
        }
    }

    func submitACHPayment(
        _ viewModel: ACHFormViewModel,
        request: PayabliPaymentRequest,
        customerId: Int,
        completion: @escaping PayabliPaymentCompletion
    ) async {
        guard viewModel.isValid else {
            viewModel.endSubmission(error: Self.preflightError)
            return
        }
        guard let config, let getpaid else {
            let error = Self.notConfiguredError
            viewModel.endSubmission(error: error)
            completion(nil, error)
            return
        }

        viewModel.beginSubmission()
        do {
            let result = try await getpaid.chargeACH(
                payload: viewModel.makePayload(),
                request: request,
                customerId: customerId,
                entryPoint: config.entryPoint
            )
            viewModel.endSubmission()
            completion(result, nil)
        } catch {
            viewModel.endSubmission(error: error)
            completion(nil, error)
        }
    }

    // MARK: - Button title

    func formatPayButtonTitle(request: PayabliPaymentRequest) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = request.currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        if let formatted = formatter.string(from: request.totalAmount as NSDecimalNumber) {
            return "Pay \(formatted)"
        }
        return "Pay"
    }
}
