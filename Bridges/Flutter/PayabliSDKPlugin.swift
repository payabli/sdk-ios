import Flutter
import UIKit
import PayabliSDKCore
import PayabliSDKPayIn

/// Flutter `MethodChannel` plugin (`com.payabli.sdk/tokenization`) bridging
/// Dart calls into the native PayabliSDK.
///
/// See PRD FR-7 and RFC-0001 §5, Phase 9.
///
/// **Authentication model:** the Dart side must fetch the access token from
/// its own backend and pass it in via the `configure` channel call. When the
/// SDK needs to refresh, it invokes the `refreshToken` channel call back on
/// the Dart side, which delegates to the partner backend.
public final class PayabliSDKPlugin: NSObject, FlutterPlugin {
    public static let channelName = "com.payabli.sdk/tokenization"

    private let channel: FlutterMethodChannel

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = PayabliSDKPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configure":
            guard let args = call.arguments as? [String: Any],
                  let config = buildConfig(args) else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing config", details: nil))
                return
            }
            Task { @MainActor in
                PayabliPayIn.shared.configure(config: config, theme: .default)
                result(nil)
            }

        case "tokenize":
            guard let args = call.arguments as? [String: Any],
                  let typeRaw = args["type"] as? Int,
                  let type = PayabliPaymentType(rawValue: typeRaw),
                  let customerId = args["customerId"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing type/customerId", details: nil))
                return
            }
            Task { @MainActor in
                guard let root = UIApplication.shared.windows.first?.rootViewController else {
                    result(FlutterError(code: "NO_WINDOW", message: "No root VC", details: nil))
                    return
                }
                let vc = PayabliPayIn.shared.createTokenizationViewController(
                    type: type,
                    customerId: customerId
                ) { token, error in
                    if let token { result(["token": token]) }
                    else { result(FlutterError(code: "TOKENIZE_FAILED", message: error?.localizedDescription, details: nil)) }
                }
                root.present(vc, animated: true)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func buildConfig(_ args: [String: Any]) -> PayabliConfig? {
        guard let accessToken = args["accessToken"] as? String,
              let entryPoint = args["entryPoint"] as? String,
              let envRaw = args["environment"] as? Int,
              let env = PayabliEnvironment(rawValue: envRaw) else {
            return nil
        }

        // Token refresh: call back into Dart via `refreshToken`. The Dart side
        // must delegate to the partner backend and return a string.
        let channel = self.channel
        let tokenProvider: PayabliTokenRefresh = { @Sendable [channel] in
            try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in
                    channel.invokeMethod("refreshToken", arguments: nil) { result in
                        if let token = result as? String {
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

        return PayabliConfig(
            accessToken: accessToken,
            tokenProvider: tokenProvider,
            entryPoint: entryPoint,
            environment: env
        )
    }
}
