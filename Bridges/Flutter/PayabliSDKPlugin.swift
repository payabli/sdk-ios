import Flutter
import UIKit
import PayabliSDKCore
import PayabliSDKTapToPay

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
              let environment = PayabliEnvironment(rawValue: envRaw) else {
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
        guard let args = arguments as? [String: Any],
              let amount = args["amount"] as? Double else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing amount",
                details: nil
            ))
            return
        }

        let typeRaw = (args["type"] as? Int) ?? 0
        let serviceFee = (args["serviceFee"] as? Double) ?? 0
        let amountNumber = NSDecimalNumber(value: amount)
        let serviceFeeNumber = NSDecimalNumber(value: serviceFee)
        let customer = (args["customer"] as? [String: Any]).map(Self.customerObjC(from:))
        let order = (args["order"] as? [String: Any]).map(Self.orderObjC(from:))

        ttp.charge(
            amount: amountNumber,
            type: typeRaw,
            serviceFee: serviceFeeNumber,
            customer: customer,
            order: order
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
              let activationCode = args["activationCode"] as? String else {
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
        PayabliTTPCustomerDataObjC(
            firstName: dict["firstName"] as? String,
            lastName: dict["lastName"] as? String,
            customerNumber: dict["customerNumber"] as? String,
            email: dict["email"] as? String,
            phone: dict["phone"] as? String
        )
    }

    private static func orderObjC(from dict: [String: Any]) -> PayabliTTPOrderDataObjC {
        PayabliTTPOrderDataObjC(
            orderId: dict["orderId"] as? String,
            orderDescription: dict["orderDescription"] as? String,
            invoiceNumber: dict["invoiceNumber"] as? String
        )
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
