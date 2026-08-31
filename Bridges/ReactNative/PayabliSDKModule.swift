import Foundation
import PayabliSDKCore
import PayabliSDKPayInPaymentFlow
import PayabliSDKTapToPay
import UIKit

#if canImport(React)
    import React
#endif

/// React Native Native Module bridging the bilingual `@objc` surface of
/// `PayabliSDKTapToPay` and `PayabliSDKPayInPaymentFlow` to JavaScript.
/// Inherits `RCTEventEmitter`, which pushes lifecycle events to JS without
/// polling.
///
/// ## Protocol
///
/// Methods (resolver/rejecter pattern, all `@objc`):
///   - `configure(config, resolver, rejecter)` — accessToken, entryPoint,
///     appId, environment.
///   - `initialize(resolver, rejecter)`
///   - `charge(params, resolver, rejecter)` — amount, type, serviceFee,
///     customer, order. Resolves with `{paymentTransId}`.
///   - `activateDevice(activationCode, resolver, rejecter)`
///   - `getSessionState(resolver, rejecter)` — resolves the int raw value
///     of the current `PayabliTTPSessionState`.
///   - `resolveTokenRefresh(token)` / `rejectTokenRefresh(reason)` —
///     responses to the `TTPTokenRefreshRequested` event.
///   - `configurePayInPaymentFlow(config, resolver, rejecter)` — entryPoint,
///     environment.
///   - `addCard(params, resolver, rejecter)`
///   - `addACH(params, resolver, rejecter)`
///   - `resolvePayInPaymentFlowAccessToken(token)` /
///     `rejectPayInPaymentFlowAccessToken(reason)` — responses to the
///     `PayInPaymentFlowAccessTokenRequested` event.
///
/// Events (RCTEventEmitter):
///   - `TTPEvent`: `{code: Int, payload: {...}}` per `PayabliTTPEvent`.
///   - `TTPTokenRefreshRequested`: signals JS to fetch a fresh token from
///     its own backend; resolve via `resolveTokenRefresh:`.
///   - `PayInPaymentFlowAccessTokenRequested`: signals JS to fetch a scoped
///     PayIn token from its own backend; resolve via
///     `resolvePayInPaymentFlowAccessToken:`.
///
/// ## Authentication
///
/// JS obtains the access token from its own backend and passes it via
/// `configure`. When the SDK needs to refresh, this module emits
/// `TTPTokenRefreshRequested`; JS hits its backend and calls
/// `resolveTokenRefresh:` (or `rejectTokenRefresh:` on failure). The token
/// refresh is single-flight — concurrent refresh requests are coalesced.
@objc(PayabliSDKModule)
public final class PayabliSDKModule: RCTEventEmitter {
    // MARK: - RCTEventEmitter overrides

    @objc override public static func requiresMainQueueSetup() -> Bool {
        true
    }

    @objc override public func supportedEvents() -> [String]! {
        [
            "TTPEvent",
            "TTPTokenRefreshRequested",
            "PayInPaymentFlowAccessTokenRequested"
        ]
    }

    // MARK: - State

    private var ttp: PayabliTTP?
    private var eventToken: PayabliTTPEventToken?
    private var payInPaymentFlow: PayabliPayInPaymentFlow?
    private var pendingRefresh: CheckedContinuation<String, Error>?
    private var pendingPayInAccessToken: CheckedContinuation<String, Error>?
    private let refreshQueue = DispatchQueue(label: "com.payabli.sdk.rn.refresh")
    private let payInAccessTokenQueue = DispatchQueue(label: "com.payabli.sdk.rn.payin-token")

    // MARK: - configure

    @objc public func configure(
        _ config: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let accessToken = config["accessToken"] as? String,
              let entryPoint = config["entryPoint"] as? String,
              let appId = config["appId"] as? String,
              let envRaw = config["environment"] as? Int,
              let environment = PayabliEnvironment(rawValue: envRaw)
        else {
            reject("INVALID_ARGS", "Missing accessToken/entryPoint/appId/environment", nil)
            return
        }

        let tokenProvider: PayabliTokenRefresh = { @Sendable [weak self] in
            try await withCheckedThrowingContinuation { continuation in
                guard let self else {
                    continuation.resume(throwing: PayabliGenericError(
                        code: .tokenExpired,
                        reason: "Native module deallocated"
                    ))
                    return
                }
                self.refreshQueue.sync {
                    // Coalesce concurrent refreshes: only emit the JS event
                    // for the first caller; subsequent waiters share the
                    // same continuation outcome.
                    if self.pendingRefresh == nil {
                        self.pendingRefresh = continuation
                        DispatchQueue.main.async {
                            self.sendEvent(withName: "TTPTokenRefreshRequested", body: nil)
                        }
                    } else {
                        // Best effort: RN offers no multi-await semantics, so a
                        // second caller arriving during a refresh gets an error.
                        continuation.resume(throwing: PayabliGenericError(
                            code: .tokenExpired,
                            reason: "A token refresh is already in flight"
                        ))
                    }
                }
            }
        }

        Task { @MainActor in
            self.eventToken?.cancel()
            self.eventToken = nil

            // The initialiser rejects an access token that cannot be sent as a header
            // and an empty entry point, both of which arrive from the JS side.
            let ttp: PayabliTTP
            do {
                ttp = try PayabliTTP(
                    accessToken: accessToken,
                    tokenProvider: tokenProvider,
                    entryPoint: entryPoint,
                    appId: appId,
                    environment: environment
                )
            } catch {
                reject("INVALID_CONFIGURATION", error.localizedDescription, error)
                return
            }
            self.ttp = ttp
            self.subscribeEvents(on: ttp)
            resolve(nil)
        }
    }

    // MARK: - initialize

    @objc public func initialize(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let ttp else {
            reject("NOT_CONFIGURED", "Call configure() before initialize()", nil)
            return
        }
        ttp.initialize { error in
            if let error {
                reject(error.rnCode(default: "INIT_FAILED"), error.rnMessage, error)
            } else {
                resolve(nil)
            }
        }
    }

    // MARK: - charge

    @objc public func charge(
        _ params: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let ttp else {
            reject("NOT_CONFIGURED", "Call configure() before charge()", nil)
            return
        }
        guard let pdDict = params["paymentDetails"] as? [String: Any],
              let amountValue = (pdDict["amount"] as? NSNumber)
        else {
            reject("INVALID_ARGS", "Missing paymentDetails.amount", nil)
            return
        }
        let typeRaw = (params["type"] as? Int) ?? 0
        let serviceFeeValue = (pdDict["serviceFee"] as? NSNumber) ?? 0
        // Pass through nil so the SDK omits `currency` from `/initiate` and the
        // backend authorizes in the merchant's configured processor currency.
        let currency = pdDict["currency"] as? String
        let paymentDescription = pdDict["paymentDescription"] as? String

        let paymentDetails = PayabliTTPPaymentDetailsObjC(
            amount: NSDecimalNumber(decimal: amountValue.decimalValue),
            serviceFee: NSDecimalNumber(decimal: serviceFeeValue.decimalValue),
            currency: currency,
            paymentDescription: paymentDescription
        )

        let customer = (params["customer"] as? [String: Any]).map(Self.customerObjC(from:))
        let invoice = (params["invoice"] as? [String: Any]).map(Self.invoiceObjC(from:))
        let orderDescription = params["orderDescription"] as? String

        ttp.charge(
            type: typeRaw,
            paymentDetails: paymentDetails,
            customer: customer,
            invoice: invoice,
            orderDescription: orderDescription
        ) { result, error in
            if let result {
                resolve(["paymentTransId": result.paymentTransId])
            } else if let error {
                reject(error.rnCode(default: "CHARGE_FAILED"), error.rnMessage, error)
            } else {
                reject("CHARGE_FAILED", "Charge returned neither result nor error", nil)
            }
        }
    }

    // MARK: - activateDevice

    @objc public func activateDevice(
        _ activationCode: NSString,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let ttp else {
            reject("NOT_CONFIGURED", "Call configure() before activateDevice()", nil)
            return
        }
        ttp.activateDevice(activationCode: activationCode as String) { error in
            if let error {
                reject(error.rnCode(default: "ACTIVATION_FAILED"), error.rnMessage, error)
            } else {
                resolve(nil)
            }
        }
    }

    // MARK: - getSessionState

    @objc public func getSessionState(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        Task { @MainActor in
            let raw = self.ttp?.sessionState.rawValue ?? PayabliTTPSessionState.idle.rawValue
            resolve(raw)
        }
    }

    // MARK: - Token refresh response

    @objc public func resolveTokenRefresh(_ token: NSString) {
        refreshQueue.sync {
            self.pendingRefresh?.resume(returning: token as String)
            self.pendingRefresh = nil
        }
    }

    @objc public func rejectTokenRefresh(_ reason: NSString) {
        refreshQueue.sync {
            self.pendingRefresh?.resume(throwing: PayabliGenericError(
                code: .tokenExpired,
                reason: reason as String
            ))
            self.pendingRefresh = nil
        }
    }

    // MARK: - PayIn payment flow

    @objc public func configurePayInPaymentFlow(
        _ config: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let entryPoint = config["entryPoint"] as? String,
              let envRaw = config["environment"] as? Int,
              let environment = PayabliEnvironment(rawValue: envRaw)
        else {
            reject("INVALID_ARGS", "Missing entryPoint/environment", nil)
            return
        }

        let accessTokenProvider: PayabliPayInPaymentFlowAccessTokenProvider = { @Sendable [weak self] in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                guard let self else {
                    continuation.resume(throwing: PayabliGenericError(
                        code: .missingToken,
                        reason: "Native module deallocated"
                    ))
                    return
                }
                self.payInAccessTokenQueue.sync {
                    if self.pendingPayInAccessToken == nil {
                        self.pendingPayInAccessToken = continuation
                        DispatchQueue.main.async {
                            self.sendEvent(withName: "PayInPaymentFlowAccessTokenRequested", body: nil)
                        }
                    } else {
                        continuation.resume(throwing: PayabliGenericError(
                            code: .missingToken,
                            reason: "A PayIn access token request is already in flight"
                        ))
                    }
                }
            }
        }

        Task { @MainActor in
            self.payInPaymentFlow = PayabliPayInPaymentFlow(
                entryPoint: entryPoint,
                environment: environment,
                accessTokenProvider: accessTokenProvider
            )
            resolve(nil)
        }
    }

    @objc public func addCard(
        _ params: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let payInPaymentFlow else {
            reject("NOT_CONFIGURED", "Call PayabliPayInPaymentFlow.configure() before addCard()", nil)
            return
        }
        guard let cardNumber = params["cardNumber"] as? String,
              let expiration = params["expiration"] as? String,
              let cardholderName = params["cardholderName"] as? String,
              let cvv = params["cvv"] as? String,
              let billingZip = params["billingZip"] as? String
        else {
            reject("INVALID_ARGS", "Missing required card fields", nil)
            return
        }

        let card = PayabliPayInPaymentFlowCardData(
            cardNumber: cardNumber,
            expiration: expiration,
            cardholderName: cardholderName,
            cvv: cvv,
            billingZip: billingZip
        )
        addPaymentMethod(
            .card(card),
            options: Self.payInOptions(from: params),
            component: payInPaymentFlow,
            resolve: resolve,
            reject: reject
        )
    }

    @objc public func addACH(
        _ params: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let payInPaymentFlow else {
            reject("NOT_CONFIGURED", "Call PayabliPayInPaymentFlow.configure() before addACH()", nil)
            return
        }
        guard let accountNumber = params["accountNumber"] as? String,
              let accountType = params["accountType"] as? String,
              let resolvedAccountType = PayabliPayInPaymentFlowACHAccountType(rawValue: accountType),
              let holderName = params["holderName"] as? String,
              let routingNumber = params["routingNumber"] as? String
        else {
            reject("INVALID_ARGS", "Missing required ACH fields", nil)
            return
        }

        let ach = PayabliPayInPaymentFlowACHData(
            accountNumber: accountNumber,
            accountType: resolvedAccountType,
            holderName: holderName,
            routingNumber: routingNumber,
            secCode: (params["secCode"] as? String).flatMap(PayabliPayInPaymentFlowACHSecCode.init(rawValue:)),
            holderType: (params["holderType"] as? String).flatMap(PayabliPayInPaymentFlowACHHolderType.init(rawValue:))
        )
        addPaymentMethod(
            .ach(ach),
            options: Self.payInOptions(from: params),
            component: payInPaymentFlow,
            resolve: resolve,
            reject: reject
        )
    }

    @objc public func resolvePayInPaymentFlowAccessToken(_ token: NSString) {
        payInAccessTokenQueue.sync {
            self.pendingPayInAccessToken?.resume(returning: token as String)
            self.pendingPayInAccessToken = nil
        }
    }

    @objc public func rejectPayInPaymentFlowAccessToken(_ reason: NSString) {
        payInAccessTokenQueue.sync {
            self.pendingPayInAccessToken?.resume(throwing: PayabliGenericError(
                code: .missingToken,
                reason: reason as String
            ))
            self.pendingPayInAccessToken = nil
        }
    }

    private func addPaymentMethod(
        _ input: PayabliPayInPaymentFlowInput,
        options: PayabliPayInPaymentFlowOptions,
        component: PayabliPayInPaymentFlow,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task { @MainActor in
            do {
                let result = try await component.addPaymentMethod(input, options: options)
                resolve(Self.storedPaymentMethodMap(result))
            } catch {
                let nsError = error as NSError
                reject(nsError.rnCode(default: "PAYIN_PAYMENT_FLOW_FAILED"), nsError.rnMessage, nsError)
            }
        }
    }

    // MARK: - Event subscription

    private func subscribeEvents(on ttp: PayabliTTP) {
        eventToken = ttp.addEventListener { [weak self] code, payload in
            let safePayload = (payload as? [String: Any]) ?? [:]
            self?.sendEvent(withName: "TTPEvent", body: [
                "code": code.rawValue,
                "payload": safePayload
            ])
        }
    }

    // MARK: - Argument helpers

    private static func customerObjC(from dict: [String: Any]) -> PayabliTTPCustomerDataObjC {
        let customerId = (dict["customerId"] as? Int).map { NSNumber(value: $0) }
        return PayabliTTPCustomerDataObjC(
            firstName: dict["firstName"] as? String,
            lastName: dict["lastName"] as? String,
            customerNumber: dict["customerNumber"] as? String,
            email: dict["email"] as? String,
            phone: dict["phone"] as? String,
            customerId: customerId,
            company: dict["company"] as? String,
            billingAddress1: dict["billingAddress1"] as? String,
            billingAddress2: dict["billingAddress2"] as? String,
            billingCity: dict["billingCity"] as? String,
            billingState: dict["billingState"] as? String,
            billingZip: dict["billingZip"] as? String,
            billingCountry: dict["billingCountry"] as? String,
            billingPhone: dict["billingPhone"] as? String,
            billingEmail: dict["billingEmail"] as? String,
            shippingAddress1: dict["shippingAddress1"] as? String,
            shippingAddress2: dict["shippingAddress2"] as? String,
            shippingCity: dict["shippingCity"] as? String,
            shippingState: dict["shippingState"] as? String,
            shippingZip: dict["shippingZip"] as? String,
            shippingCountry: dict["shippingCountry"] as? String
        )
    }

    private static func invoiceObjC(from dict: [String: Any]) -> PayabliTTPInvoiceDataObjC {
        PayabliTTPInvoiceDataObjC(
            invoiceNumber: dict["invoiceNumber"] as? String
        )
    }

    private static func payInOptions(from params: NSDictionary) -> PayabliPayInPaymentFlowOptions {
        PayabliPayInPaymentFlowOptions(
            achValidation: params["achValidation"] as? Bool,
            createAnonymous: params["createAnonymous"] as? Bool,
            forceCustomerCreation: params["forceCustomerCreation"] as? Bool,
            temporary: params["temporary"] as? Bool,
            source: params["source"] as? String
        )
    }

    private static func storedPaymentMethodMap(
        _ method: PayabliPayInPaymentFlowStoredPaymentMethod
    ) -> [String: Any] {
        var map: [String: Any] = [
            "responseText": method.responseText,
            "apiResponse": dictionary(from: method.apiResponse)
        ]
        if let storedMethodId = method.storedMethodId {
            map["storedMethodId"] = storedMethodId
        }
        if let methodReferenceId = method.methodReferenceId {
            map["methodReferenceId"] = methodReferenceId
        }
        if let resultCode = method.resultCode {
            map["resultCode"] = resultCode
        }
        if let resultText = method.resultText {
            map["resultText"] = resultText
        }
        if let customerId = method.customerId {
            map["customerId"] = customerId
        }
        return map
    }

    private static func dictionary(
        from response: PayabliPayInPaymentFlowTokenStorageAPIResponse
    ) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(response),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ["responseText": response.responseText]
        }
        return object
    }
}

// MARK: - NSError → RN error code/message

private extension NSError {
    func rnCode(default fallback: String) -> String {
        if domain == "com.payabli.ttp" {
            return "TTP_\(self.code)"
        }
        return fallback
    }

    var rnMessage: String {
        userInfo[NSLocalizedDescriptionKey] as? String ?? localizedDescription
    }
}

// MARK: - RCTEventEmitter / RCTPromiseResolveBlock stubs

//
// These typealiases let the module compile when it's pulled into a host
// project that doesn't import React. The host's React headers (when present)
// take precedence over these stubs by virtue of the module being compiled
// against the host's framework search paths.
//
// In a real RN integration the host's `React.framework` provides:
//   - typealias RCTPromiseResolveBlock = (Any?) -> Void
//   - typealias RCTPromiseRejectBlock  = (String?, String?, Error?) -> Void
//   - open class RCTEventEmitter: RCTBridgeModule { ... }
//
// If you copy this file into a project that already links React these
// typealiases will be shadowed — they're only here for type-checker sanity
// when the file is read in isolation (e.g., in CI lint runs that don't
// pull a React Pod).

#if !canImport(React)
    public typealias RCTPromiseResolveBlock = (Any?) -> Void
    public typealias RCTPromiseRejectBlock = (String?, String?, Error?) -> Void

    open class RCTEventEmitter: NSObject {
        open class func requiresMainQueueSetup() -> Bool {
            true
        }

        open func supportedEvents() -> [String]! {
            []
        }

        open func sendEvent(withName name: String, body: Any?) {}
        override public init() {
            super.init()
        }
    }
#endif
