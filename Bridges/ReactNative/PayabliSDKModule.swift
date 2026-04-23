import Foundation
import UIKit
import PayabliSDKCore
import PayabliSDKPayIn

/// React Native Native Module architecture for PayabliSDK (PRD FR-9.1).
///
/// **Authentication model:** the JS side obtains the access token from its
/// own backend (which holds the `clientSecret` server-side) and passes it in
/// via `configure`. Token refresh is delegated back to JS via an event.
@objc(PayabliSDKModule)
public final class PayabliSDKModule: NSObject {

    @objc public static func requiresMainQueueSetup() -> Bool { true }

    private var tokenRefreshResolver: ((String) -> Void)?

    @objc public func configure(
        _ config: NSDictionary,
        resolver resolve: @escaping (Any?) -> Void,
        rejecter reject: @escaping (String, String, Error?) -> Void
    ) {
        guard let accessToken = config["accessToken"] as? String,
              let entryPoint = config["entryPoint"] as? String,
              let envRaw = config["environment"] as? Int,
              let env = PayabliEnvironment(rawValue: envRaw) else {
            reject("INVALID_ARGS", "Missing config fields", nil)
            return
        }

        Task { @MainActor in
            PayabliPayIn.shared.configure(
                config: PayabliConfig(
                    accessToken: accessToken,
                    // TODO: wire a tokenProvider that emits an RN event and
                    // awaits a response from the JS side via `resolveTokenRefresh`.
                    tokenProvider: nil,
                    entryPoint: entryPoint,
                    environment: env
                ),
                theme: .default
            )
            resolve(nil)
        }
    }

    @objc public func tokenize(
        _ typeRaw: Int,
        customerId: Int,
        resolver resolve: @escaping (Any?) -> Void,
        rejecter reject: @escaping (String, String, Error?) -> Void
    ) {
        guard let type = PayabliPaymentType(rawValue: typeRaw) else {
            reject("INVALID_TYPE", "Unknown payment type", nil)
            return
        }
        Task { @MainActor in
            guard let root = UIApplication.shared.windows.first?.rootViewController else {
                reject("NO_WINDOW", "No root view controller", nil)
                return
            }
            let vc = PayabliPayIn.shared.createTokenizationViewController(
                type: type,
                customerId: customerId
            ) { token, error in
                if let token { resolve(["token": token]) }
                else { reject("TOKENIZE_FAILED", error?.localizedDescription ?? "Unknown error", error) }
            }
            root.present(vc, animated: true)
        }
    }
}
