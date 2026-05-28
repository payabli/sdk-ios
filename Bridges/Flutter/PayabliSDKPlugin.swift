import Flutter
import PayabliSDKCore
import PayabliSDKPaymentMethod
import PayabliSDKTapToPay
import UIKit

/// Flutter plugin bridging Dart calls into the native `PayabliSDKTapToPay`
/// surface. Exposes the bilingual `@objc` companions added in
/// `Sources/PayabliSDKTapToPay/PayabliTTP+*.swift`.
///
/// Two channels:
///   - `com.payabli.sdk/taptopay` (`MethodChannel`): request/response RPC for
///     `configure`, `initialize`, `charge`, `activateDevice`, `getSessionState`.
///   - `com.payabli.sdk/taptopay/events` (`EventChannel`): one-way stream of
///     lifecycle events (`PayabliTTPEvent`) flattened to
///     `{"code": Int, "payload": [String: Any]}` per event.
///
/// **Authentication model:** the Dart side fetches the access token from its
/// own backend and passes it in via the `configure` channel call. When the
/// SDK needs to refresh, it invokes the `refreshToken` channel call back on
/// the Dart side, which delegates to the partner backend.
public final class PayabliSDKPlugin: NSObject, FlutterPlugin {
    public static let methodChannelName = "com.payabli.sdk/taptopay"
    public static let eventChannelName = "com.payabli.sdk/taptopay/events"

    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private let eventSink = EventSinkBox()

    private var ttp: PayabliTTP?
    private var eventToken: PayabliTTPEventToken?
    private var paymentMethod: PayabliPaymentMethod?

    init(methodChannel: FlutterMethodChannel, eventChannel: FlutterEventChannel) {
        self.methodChannel = methodChannel
        self.eventChannel = eventChannel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = PayabliSDKPlugin(methodChannel: methodChannel, eventChannel: eventChannel)
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - MethodChannel dispatch

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configure":
            handleConfigure(call.arguments, result: result)
        case "initialize":
            handleInitialize(result: result)
        case "charge":
            handleCharge(call.arguments, result: result)
        case "activateDevice":
            handleActivateDevice(call.arguments, result: result)
        case "getSessionState":
            handleGetSessionState(result: result)
        case "configurePaymentMethod":
            handleConfigurePaymentMethod(call.arguments, result: result)
        case "addCard":
            handleAddCard(call.arguments, result: result)
        case "addACH":
            handleAddACH(call.arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - configure

    private func handleConfigure(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let accessToken = args["accessToken"] as? String,
              let entryPoint = args["entryPoint"] as? String,
              let appId = args["appId"] as? String,
              let envRaw = args["environment"] as? Int,
              let environment = PayabliEnvironment(rawValue: envRaw)
        else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing accessToken/entryPoint/appId/environment",
                details: nil
            ))
            return
        }

        let methodChannel = self.methodChannel
        let tokenProvider: PayabliTokenRefresh = { @Sendable [methodChannel] in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                Task { @MainActor in
                    methodChannel.invokeMethod("refreshToken", arguments: nil) { value in
                        if let token = value as? String {
                            continuation.resume(returning: token)
                        } else {
                            continuation.resume(throwing: PayabliGenericError(
                                code: .tokenExpired,
                                reason: "Dart side did not return a refreshed token"
                            ))
                        }
                    }
                }
            }
        }

        Task { @MainActor in
            // Re-create the facade if configure() is called again. Cancel any
            // previous event subscription so we don't leak.
            self.eventToken?.cancel()
            self.eventToken = nil

            let ttp = PayabliTTP(
                accessToken: accessToken,
                tokenProvider: tokenProvider,
                entryPoint: entryPoint,
                appId: appId,
                environment: environment
            )
            self.ttp = ttp
            self.subscribeEvents(on: ttp)
            result(nil)
        }
    }

    // MARK: - initialize

    private func handleInitialize(result: @escaping FlutterResult) {
        guard let ttp else {
            result(FlutterError(
                code: "NOT_CONFIGURED",
                message: "Call configure() before initialize()",
                details: nil
            ))
            return
        }
        ttp.initialize { error in
            if let error {
                result(error.toFlutterError(defaultCode: "INIT_FAILED"))
            } else {
                result(nil)
            }
        }
    }

    // MARK: - charge

    private func handleCharge(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let ttp else {
            result(FlutterError(
                code: "NOT_CONFIGURED",
                message: "Call configure() before charge()",
                details: nil
            ))
            return
        }
        guard let args = arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }
        guard let pdDict = args["paymentDetails"] as? [String: Any],
              let amount = pdDict["amount"] as? Double
        else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing paymentDetails.amount",
                details: nil
            ))
            return
        }

        let typeRaw = (args["type"] as? Int) ?? 0
        let serviceFee = (pdDict["serviceFee"] as? Double) ?? 0
        // Pass through nil so the SDK omits `currency` from `/initiate` and the
        // backend authorizes in the merchant's configured processor currency.
        let currency = pdDict["currency"] as? String
        let paymentDescription = pdDict["paymentDescription"] as? String

        let paymentDetails = PayabliTTPPaymentDetailsObjC(
            amount: NSDecimalNumber(value: amount),
            serviceFee: NSDecimalNumber(value: serviceFee),
            currency: currency,
            paymentDescription: paymentDescription
        )

        let customer = (args["customer"] as? [String: Any]).map(Self.customerObjC(from:))
        let invoice = (args["invoice"] as? [String: Any]).map(Self.invoiceObjC(from:))
        let orderDescription = args["orderDescription"] as? String

        ttp.charge(
            type: typeRaw,
            paymentDetails: paymentDetails,
            customer: customer,
            invoice: invoice,
            orderDescription: orderDescription
        ) { txnResult, error in
            if let txnResult {
                result(["paymentTransId": txnResult.paymentTransId])
            } else if let error {
                result(error.toFlutterError(defaultCode: "CHARGE_FAILED"))
            } else {
                result(FlutterError(
                    code: "CHARGE_FAILED",
                    message: "Charge returned neither result nor error",
                    details: nil
                ))
            }
        }
    }

    // MARK: - activateDevice

    private func handleActivateDevice(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let ttp else {
            result(FlutterError(
                code: "NOT_CONFIGURED",
                message: "Call configure() before activateDevice()",
                details: nil
            ))
            return
        }
        guard let args = arguments as? [String: Any],
              let activationCode = args["activationCode"] as? String
        else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing activationCode",
                details: nil
            ))
            return
        }
        ttp.activateDevice(activationCode: activationCode) { error in
            if let error {
                result(error.toFlutterError(defaultCode: "ACTIVATION_FAILED"))
            } else {
                result(nil)
            }
        }
    }

    // MARK: - getSessionState

    private func handleGetSessionState(result: @escaping FlutterResult) {
        Task { @MainActor in
            let raw = self.ttp?.sessionState.rawValue ?? PayabliTTPSessionState.idle.rawValue
            result(raw)
        }
    }

    // MARK: - Payment Method

    private func handleConfigurePaymentMethod(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let entryPoint = args["entryPoint"] as? String,
              let envRaw = args["environment"] as? Int,
              let environment = PayabliEnvironment(rawValue: envRaw)
        else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing entryPoint/environment",
                details: nil
            ))
            return
        }

        let methodChannel = self.methodChannel
        let accessTokenProvider: PayabliPaymentMethodAccessTokenProvider = { @Sendable [methodChannel] in
            try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in
                    methodChannel.invokeMethod("accessToken", arguments: nil) { value in
                        if let token = value as? String {
                            continuation.resume(returning: token)
                        } else {
                            continuation.resume(throwing: PayabliGenericError(
                                code: .missingToken,
                                reason: "Dart side did not return a payment method access token"
                            ))
                        }
                    }
                }
            }
        }

        Task { @MainActor in
            self.paymentMethod = PayabliPaymentMethod(
                entryPoint: entryPoint,
                environment: environment,
                accessTokenProvider: accessTokenProvider
            )
            result(nil)
        }
    }

    private func handleAddCard(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let paymentMethod else {
            result(FlutterError(code: "NOT_CONFIGURED", message: "Call configurePaymentMethod() first", details: nil))
            return
        }
        guard let args = arguments as? [String: Any],
              let cardNumber = args["cardNumber"] as? String,
              let expiration = args["expiration"] as? String,
              let cardholderName = args["cardholderName"] as? String,
              let cvv = args["cvv"] as? String,
              let billingZip = args["billingZip"] as? String
        else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing required card fields: cardNumber, expiration, cardholderName, cvv, billingZip",
                details: nil
            ))
            return
        }

        let card = PayabliCardPaymentMethodData(
            cardNumber: cardNumber,
            expiration: expiration,
            cardholderName: cardholderName,
            cvv: cvv,
            billingZip: billingZip
        )
        handleAddPaymentMethod(
            .card(card),
            options: paymentMethodOptions(from: args),
            component: paymentMethod,
            result: result
        )
    }

    private func handleAddACH(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let paymentMethod else {
            result(FlutterError(code: "NOT_CONFIGURED", message: "Call configurePaymentMethod() first", details: nil))
            return
        }
        guard let args = arguments as? [String: Any],
              let accountNumber = args["accountNumber"] as? String,
              let accountType = args["accountType"] as? String,
              let resolvedAccountType = PayabliACHAccountType(rawValue: accountType),
              let holderName = args["holderName"] as? String,
              let routingNumber = args["routingNumber"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required ACH fields", details: nil))
            return
        }

        let ach = PayabliACHPaymentMethodData(
            accountNumber: accountNumber,
            accountType: resolvedAccountType,
            holderName: holderName,
            routingNumber: routingNumber,
            secCode: (args["secCode"] as? String).flatMap(PayabliACHSecCode.init(rawValue:)),
            holderType: (args["holderType"] as? String).flatMap(PayabliACHHolderType.init(rawValue:))
        )
        handleAddPaymentMethod(
            .ach(ach),
            options: paymentMethodOptions(from: args),
            component: paymentMethod,
            result: result
        )
    }

    private func handleAddPaymentMethod(
        _ paymentMethod: PayabliPaymentMethodInput,
        options: PayabliPaymentMethodOptions,
        component: PayabliPaymentMethod,
        result: @escaping FlutterResult
    ) {
        Task { @MainActor in
            do {
                let method = try await component.addPaymentMethod(paymentMethod, options: options)
                result(Self.storedPaymentMethodMap(method))
            } catch {
                result((error as NSError).toFlutterError(defaultCode: "PAYMENT_METHOD_FAILED"))
            }
        }
    }

    private func paymentMethodOptions(from args: [String: Any]) -> PayabliPaymentMethodOptions {
        PayabliPaymentMethodOptions(
            achValidation: args["achValidation"] as? Bool,
            createAnonymous: args["createAnonymous"] as? Bool,
            forceCustomerCreation: args["forceCustomerCreation"] as? Bool,
            temporary: args["temporary"] as? Bool,
            source: args["source"] as? String
        )
    }

    // MARK: - Event subscription

    private func subscribeEvents(on ttp: PayabliTTP) {
        let sinkBox = self.eventSink
        eventToken = ttp.addEventListener { code, payload in
            // payload is `[String: Any]`; force-cast keys for the Flutter
            // wire format. All known PayabliTTPEvent payloads use `String`
            // values.
            let safePayload = (payload as? [String: Any]) ?? [:]
            sinkBox.send([
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

    private static func storedPaymentMethodMap(_ method: PayabliStoredPaymentMethod) -> [String: Any] {
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

    private static func dictionary(from response: PayabliPaymentMethodAPIResponse) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(response),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }
}

// MARK: - FlutterStreamHandler

extension PayabliSDKPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink.attach(events)
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink.detach()
        return nil
    }
}

// MARK: - EventSinkBox

/// Thread-safe holder for the current `FlutterEventSink`. Allows the plugin
/// to attach/detach sinks (Flutter cancels the stream when the Dart listener
/// goes away) without dropping incoming SDK events.
private final class EventSinkBox {
    private var sink: FlutterEventSink?
    private let queue = DispatchQueue(label: "com.payabli.sdk.flutter.eventsink")

    func attach(_ sink: @escaping FlutterEventSink) {
        queue.sync { self.sink = sink }
    }

    func detach() {
        queue.sync { self.sink = nil }
    }

    func send(_ value: Any) {
        queue.sync {
            DispatchQueue.main.async { [sink] in
                sink?(value)
            }
        }
    }
}

// MARK: - NSError → FlutterError

private extension NSError {
    func toFlutterError(defaultCode: String) -> FlutterError {
        let code: String = {
            if domain == "com.payabli.ttp" {
                return "TTP_\(self.code)"
            }
            return defaultCode
        }()
        let message = userInfo[NSLocalizedDescriptionKey] as? String ?? localizedDescription
        return FlutterError(code: code, message: message, details: nil)
    }
}
