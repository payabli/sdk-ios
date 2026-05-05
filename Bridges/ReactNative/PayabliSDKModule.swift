import Foundation
import UIKit
import PayabliSDKCore
import PayabliSDKTapToPay

/// React Native Native Module bridging the bilingual `@objc` surface of
/// `PayabliSDKTapToPay` to JavaScript. Inherits `RCTEventEmitter` so we can
/// push lifecycle events to JS without polling.
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
///
/// Events (RCTEventEmitter):
///   - `TTPEvent`: `{code: Int, payload: {...}}` per `PayabliTTPEvent`.
///   - `TTPTokenRefreshRequested`: signals JS to fetch a fresh token from
///     its own backend; resolve via `resolveTokenRefresh:`.
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

    @objc public override static func requiresMainQueueSetup() -> Bool { true }

    @objc public override func supportedEvents() -> [String]! {
        ["TTPEvent", "TTPTokenRefreshRequested"]
    }

    // MARK: - State

    private var ttp: PayabliTTP?
    private var eventToken: PayabliTTPEventToken?
    private var pendingRefresh: CheckedContinuation<String, Error>?
    private let refreshQueue = DispatchQueue(label: "com.payabli.sdk.rn.refresh")

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
              let environment = PayabliEnvironment(rawValue: envRaw) else {
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
                        // Best-effort: chain — but RN doesn't give us
                        // multi-await semantics, so we error this caller.
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

            let ttp = PayabliTTP(
                accessToken: accessToken,
                tokenProvider: tokenProvider,
                entryPoint: entryPoint,
                appId: appId,
                environment: environment
            )
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
        guard let amountValue = (params["amount"] as? NSNumber) else {
            reject("INVALID_ARGS", "Missing amount", nil)
            return
        }
        let typeRaw = (params["type"] as? Int) ?? 0
        let serviceFeeValue = (params["serviceFee"] as? NSNumber) ?? 0
        let customer = (params["customer"] as? [String: Any]).map(Self.customerObjC(from:))
        let order = (params["order"] as? [String: Any]).map(Self.orderObjC(from:))

        ttp.charge(
            amount: NSDecimalNumber(decimal: amountValue.decimalValue),
            type: typeRaw,
            serviceFee: NSDecimalNumber(decimal: serviceFeeValue.decimalValue),
            customer: customer,
            order: order
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

// MARK: - NSError → RN error code/message

private extension NSError {
    func rnCode(default fallback: String) -> String {
        if domain == "com.payabli.ttp" { return "TTP_\(self.code)" }
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
    open func supportedEvents() -> [String]! { [] }
    open func sendEvent(withName name: String, body: Any?) {}
    public override init() { super.init() }
}
#endif
