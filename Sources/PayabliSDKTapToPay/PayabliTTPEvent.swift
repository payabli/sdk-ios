import Foundation
import PayabliSDKCore

/// Lifecycle events emitted by `PayabliTTP.events()` (PRD §20.1).
public enum PayabliTTPEvent: Sendable {
    case attestationStarted
    case attestationCompleted
    case configReceived
    case readerInitializing
    case readerReady
    case chargeInitiated(paymentTransId: String)
    case nfcStarted
    case nfcCompleted
    case nfcFailed(error: String)
    case updateCompleted(paymentTransId: String)
    case updateFailed(paymentTransId: String, error: String)
    case sessionExpired
    case reinitializeStarted
    case reinitializeCompleted
    case devicePendingActivation
    case activationStarted
    case activationCompleted
    case activationFailed(error: String)
    // Appended after `activationFailed` to keep declaration order aligned with
    // the `PayabliTTPEventCode` raw values, which are public API. Cases arrive at
    // the end as the SDK grows. A client of the binary framework has to cover
    // cases it cannot see, by either `default` or `@unknown default`; the latter
    // keeps the warning that says a new case arrived, which is the point of it.
    case attestationFailed(error: String)
    case configFailed(error: String)
    case termsRequired

    // What the reader is doing. The platform raises more states than these; the
    // ones it raises for a read starting, completing or failing are left out,
    // because `nfcStarted`, `nfcCompleted` and `nfcFailed` above already say so
    // and a host would otherwise be told the same thing twice.

    /// The reader cannot take a card yet.
    case readerNotReady

    /// A card is in the field.
    case cardDetected

    /// The card has been read and should be taken away.
    case cardRemovalRequested

    /// The read did not succeed and the card should be presented again.
    case cardReadRetryRequested

    /// The payer is being asked for a PIN.
    case pinEntryRequested

    /// The payer has finished entering a PIN.
    case pinEntryCompleted

    /// The prompt the platform drew is gone. The read may still resolve.
    case readerPromptDismissed
}

/// TTP-specific errors (PRD §20.2).
///
/// A charge can also throw a core `PayabliError` from opening the payment. That one is raised before the
/// card is read, so nothing was charged, and the SDK holds no payment identifier for it.
public enum PayabliTTPError: Error, Sendable {
    case notInitialized
    case invalidState(current: PayabliTTPSessionState, attempted: String)
    case notReady(current: PayabliTTPSessionState)
    case devicePendingActivation
    case attestationRevoked(reason: String)
    case attestationFailed(reason: String)
    case configFailed(reason: String)
    case readerSetupFailed(reason: String)
    case nfcFailed(reason: String, paymentTransId: String? = nil)
    case initiateFailed(reason: String)
    case updateFailed(reason: String, paymentTransId: String, capture: PayabliTTPCapture)
    case tokenExpired
    case activationFailed(reason: String)
    case networkError(reason: String)
    /// The merchant has not accepted the terms their platform requires before it
    /// will take a contactless payment. The SDK does not accept on their behalf.
    ///
    /// Appended after `networkError` to keep the `errorCode` table below
    /// append-only; those codes are public API.
    case termsNotAccepted

    /// This OS build cannot take contactless payments, and nothing the app or
    /// the merchant does reaches that. The remedy is a different device or an
    /// OS upgrade, where every other reader failure is transient or
    /// environmental.
    ///
    /// Appended after `termsNotAccepted` to keep the `errorCode` table below
    /// append-only; those codes are public API.
    case readerOSVersionNotSupported

    /// The processor refused the card. No money moved.
    case cardDeclined(paymentTransId: String)

    /// The processor answered neither an approval nor a refusal, so the SDK cannot say whether money moved.
    case outcomeUnknown(paymentTransId: String)
}

public extension PayabliTTPError {
    /// Whether this failure took money from the card.
    var capture: PayabliTTPCapture {
        switch self {
        case .cardDeclined:
            return .notCharged
        case let .nfcFailed(_, paymentTransId):
            return paymentTransId == nil ? .notCharged : .unknown
        case .outcomeUnknown:
            return .unknown
        case let .updateFailed(_, _, capture):
            return capture
        case .notInitialized, .invalidState, .notReady, .devicePendingActivation, .attestationRevoked,
             .attestationFailed, .configFailed, .readerSetupFailed, .initiateFailed, .tokenExpired,
             .activationFailed, .networkError, .termsNotAccepted, .readerOSVersionNotSupported:
            return .notCharged
        }
    }

    /// The payment this failure belongs to, or `nil` when the SDK holds no identifier for one.
    var paymentTransId: String? {
        switch self {
        case let .nfcFailed(_, paymentTransId):
            return paymentTransId
        case let .updateFailed(_, paymentTransId, _),
             let .cardDeclined(paymentTransId),
             let .outcomeUnknown(paymentTransId):
            return paymentTransId
        case .notInitialized, .invalidState, .notReady, .devicePendingActivation, .attestationRevoked,
             .attestationFailed, .configFailed, .readerSetupFailed, .initiateFailed, .tokenExpired,
             .activationFailed, .networkError, .termsNotAccepted, .readerOSVersionNotSupported:
            return nil
        }
    }
}

// MARK: - ObjC event-code mapping

/// Stable integer identifiers for each `PayabliTTPEvent` case, exposed to
/// ObjC / MAUI / sharpie consumers via `@objc`. The Swift enum keeps its
/// associated values; ObjC consumers receive the case via `code` and the
/// associated values as a `[String: Any]` payload — see
/// `PayabliTTPEvent.payload`.
///
/// Cases are numbered in declaration order on `PayabliTTPEvent` and the
/// raw values are part of the public API: do not reorder or renumber. New
/// cases must be appended at the end with a new raw value.
@objc public enum PayabliTTPEventCode: Int, Sendable {
    case attestationStarted = 0
    case attestationCompleted = 1
    case configReceived = 2
    case readerInitializing = 3
    case readerReady = 4
    case chargeInitiated = 5
    case nfcStarted = 6
    case nfcCompleted = 7
    case nfcFailed = 8
    case updateCompleted = 9
    case updateFailed = 10
    case sessionExpired = 11
    case reinitializeStarted = 12
    case reinitializeCompleted = 13
    case devicePendingActivation = 14
    case activationStarted = 15
    case activationCompleted = 16
    case activationFailed = 17
    case attestationFailed = 18
    case configFailed = 19
    case termsRequired = 20
    // 21 was `readerConfigurationProgressChanged`. Progress is a payload on the
    // session state now. The value is retired rather than reused: this package
    // has no tagged release, so every consumer resolves from source against
    // `main` and has had 21 since it merged there.
    case readerNotReady = 22
    case cardDetected = 23
    case cardRemovalRequested = 24
    case cardReadRetryRequested = 25
    case pinEntryRequested = 26
    case pinEntryCompleted = 27
    case readerPromptDismissed = 28
}

public extension PayabliTTPEvent {
    /// Returns the `PayabliTTPEventCode` for this event — used by the
    /// `addEventListener(handler:)` ObjC bridge.
    var code: PayabliTTPEventCode {
        switch self {
        case .attestationStarted: return .attestationStarted
        case .attestationCompleted: return .attestationCompleted
        case .configReceived: return .configReceived
        case .readerInitializing: return .readerInitializing
        case .readerReady: return .readerReady
        case .chargeInitiated: return .chargeInitiated
        case .nfcStarted: return .nfcStarted
        case .nfcCompleted: return .nfcCompleted
        case .nfcFailed: return .nfcFailed
        case .updateCompleted: return .updateCompleted
        case .updateFailed: return .updateFailed
        case .sessionExpired: return .sessionExpired
        case .reinitializeStarted: return .reinitializeStarted
        case .reinitializeCompleted: return .reinitializeCompleted
        case .devicePendingActivation: return .devicePendingActivation
        case .activationStarted: return .activationStarted
        case .activationCompleted: return .activationCompleted
        case .activationFailed: return .activationFailed
        case .attestationFailed: return .attestationFailed
        case .configFailed: return .configFailed
        case .termsRequired: return .termsRequired
        case .readerNotReady: return .readerNotReady
        case .cardDetected: return .cardDetected
        case .cardRemovalRequested: return .cardRemovalRequested
        case .cardReadRetryRequested: return .cardReadRetryRequested
        case .pinEntryRequested: return .pinEntryRequested
        case .pinEntryCompleted: return .pinEntryCompleted
        case .readerPromptDismissed: return .readerPromptDismissed
        }
    }

    /// Associated values for this event flattened into a dictionary suitable
    /// for ObjC / MAUI / RN consumers.
    ///
    /// Schema by case:
    ///   - `.chargeInitiated`, `.updateCompleted` → `["paymentTransId": String]`
    ///   - `.nfcFailed`, `.activationFailed`, `.attestationFailed`,
    ///     `.configFailed` → `["error": String]`
    ///   - `.updateFailed` → `["paymentTransId": String, "error": String]`
    ///   - all other cases → empty `[:]`
    ///
    /// Every `error` string here names the failure and nothing else: the case, or a
    /// wire code where the service described it. No reason travels in one, because
    /// the same case carries this SDK's words on one path and the service's on
    /// another, and the service's can quote what was submitted. The wording reaches
    /// the caller on the thrown error, which is where it can be shown to the person
    /// who can act on it.
    ///
    /// `paymentTransId` is not free text and does travel: it is what a payment is
    /// looked up by.
    var payload: [String: Any] {
        switch self {
        case let .chargeInitiated(paymentTransId),
             let .updateCompleted(paymentTransId):
            return ["paymentTransId": paymentTransId]
        case let .nfcFailed(error),
             let .activationFailed(error),
             let .attestationFailed(error),
             let .configFailed(error):
            return ["error": error]
        case let .updateFailed(paymentTransId, error):
            return ["paymentTransId": paymentTransId, "error": error]
        case .attestationStarted,
             .attestationCompleted,
             .configReceived,
             .readerInitializing,
             .readerReady,
             .nfcStarted,
             .nfcCompleted,
             .sessionExpired,
             .reinitializeStarted,
             .reinitializeCompleted,
             .devicePendingActivation,
             .activationStarted,
             .activationCompleted,
             .termsRequired,
             .readerNotReady,
             .cardDetected,
             .cardRemovalRequested,
             .cardReadRetryRequested,
             .pinEntryRequested,
             .pinEntryCompleted,
             .readerPromptDismissed:
            return [:]
        }
    }
}

// MARK: - PayabliTTPError NSError bridging

/// `PayabliTTPError` bridges to `NSError` with domain `"com.payabli.ttp"` and
/// stable per-case integer codes so ObjC / MAUI consumers can branch on the
/// `code` property without parsing localized strings. The `code` table is
/// part of the public API: do not reorder or renumber. New cases must be
/// appended at the end with a new code.
extension PayabliTTPError: CustomNSError, LocalizedError {
    public static var errorDomain: String {
        "com.payabli.ttp"
    }

    public var errorCode: Int {
        switch self {
        case .notInitialized: return 0
        case .invalidState: return 1
        case .notReady: return 2
        case .devicePendingActivation: return 3
        case .attestationRevoked: return 4
        case .attestationFailed: return 5
        case .configFailed: return 6
        case .readerSetupFailed: return 7
        case .nfcFailed: return 8
        case .initiateFailed: return 9
        case .updateFailed: return 10
        case .tokenExpired: return 11
        case .activationFailed: return 12
        case .networkError: return 13
        case .termsNotAccepted: return 14
        case .readerOSVersionNotSupported: return 15
        case .cardDeclined: return 16
        case .outcomeUnknown: return 17
        }
    }

    /// Carries `"capture"`, the raw value of ``capture``, and `"paymentTransId"` where the failure
    /// belongs to a payment, so a bridged caller can reconcile without the Swift type.
    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [NSLocalizedDescriptionKey: localizedReason, "capture": capture.rawValue]
        if let paymentTransId {
            info["paymentTransId"] = paymentTransId
        }
        return info
    }

    private var localizedReason: String {
        switch self {
        case .notInitialized:
            return "PayabliTTP has not been initialized"
        case let .invalidState(current, attempted):
            return "Invalid state \(current) for \(attempted)"
        case let .notReady(current):
            return "Reader not ready (state: \(current))"
        case .devicePendingActivation:
            return "Device is pending activation"
        case .tokenExpired:
            return "Access token expired"
        case .termsNotAccepted:
            return "Contactless payment terms have not been accepted"
        case .readerOSVersionNotSupported:
            return "This OS version does not support contactless payments"
        case .cardDeclined:
            return "The card was refused"
        case .outcomeUnknown:
            return "The payment outcome is not known"
        case let .nfcFailed(reason, _),
             let .updateFailed(reason, _, _):
            return reason
        case let .attestationRevoked(reason),
             let .attestationFailed(reason),
             let .configFailed(reason),
             let .readerSetupFailed(reason),
             let .initiateFailed(reason),
             let .activationFailed(reason),
             let .networkError(reason):
            return reason
        }
    }

    public var errorDescription: String? {
        localizedReason
    }
}

extension Error {
    /// Bridges any `Error` to an `NSError` for the `@objc` callback companions. A Payabli
    /// taxonomy is discoverable in the `"com.payabli.ttp"` domain: `PayabliTTPError` through its
    /// stable per-case `code`, a core `PayabliError` (an attestation-time provider failure, for
    /// one) through `userInfo["PayabliErrorCode"]` on domain-code `-3`. Everything else falls
    /// through Swift's default bridging.
    func toPayabliNSError() -> NSError {
        if let ttpError = self as? PayabliTTPError {
            return ttpError as NSError
        }
        if let payabliError = self as? any PayabliError {
            return NSError(
                domain: PayabliTTPError.errorDomain,
                code: -3,
                userInfo: [
                    NSLocalizedDescriptionKey: payabliError.reason,
                    "PayabliErrorCode": payabliError.code.rawValue
                ]
            )
        }
        return self as NSError
    }
}
