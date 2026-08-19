import Foundation

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
}

/// TTP-specific errors (PRD §20.2).
public enum PayabliTTPError: Error, Sendable {
    case notInitialized
    case invalidState(current: PayabliTTPSessionState, attempted: String)
    case notReady(current: PayabliTTPSessionState)
    case devicePendingActivation
    case attestationRevoked(reason: String)
    case attestationFailed(reason: String)
    case configFailed(reason: String)
    case readerSetupFailed(reason: String)
    case nfcFailed(reason: String)
    case initiateFailed(reason: String)
    case updateFailed(reason: String)
    case tokenExpired
    case activationFailed(reason: String)
    case networkError(reason: String)
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
    /// The `error` string on `.attestationFailed` and `.configFailed` names the
    /// failure and nothing else: the case, or a wire code where the service
    /// described it. No reason travels in one, because the same case carries this
    /// SDK's words on one path and the service's on another, and the service's can
    /// quote what was submitted. The wording reaches the caller on the thrown
    /// error, which is where it can be shown to the person who can act on it.
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
             .activationCompleted:
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
        }
    }

    public var errorUserInfo: [String: Any] {
        switch self {
        case .notInitialized:
            return [NSLocalizedDescriptionKey: "PayabliTTP has not been initialized"]
        case let .invalidState(current, attempted):
            return [NSLocalizedDescriptionKey: "Invalid state \(current) for \(attempted)"]
        case let .notReady(current):
            return [NSLocalizedDescriptionKey: "Reader not ready (state: \(current))"]
        case .devicePendingActivation:
            return [NSLocalizedDescriptionKey: "Device is pending activation"]
        case .tokenExpired:
            return [NSLocalizedDescriptionKey: "Access token expired"]
        case let .attestationRevoked(reason),
             let .attestationFailed(reason),
             let .configFailed(reason),
             let .readerSetupFailed(reason),
             let .nfcFailed(reason),
             let .initiateFailed(reason),
             let .updateFailed(reason),
             let .activationFailed(reason),
             let .networkError(reason):
            return [NSLocalizedDescriptionKey: reason]
        }
    }

    public var errorDescription: String? {
        errorUserInfo[NSLocalizedDescriptionKey] as? String
    }
}

extension Error {
    /// Bridges any `Error` to an `NSError` suitable for the `@objc` callback
    /// companions. `PayabliTTPError` flows through its `CustomNSError`
    /// conformance (domain `"com.payabli.ttp"` + stable per-case `code`);
    /// other errors are bridged via `as NSError` (using their existing
    /// domain — typically Swift's `Swift.Error`-bridged domain).
    func toPayabliNSError() -> NSError {
        if let ttpError = self as? PayabliTTPError {
            return ttpError as NSError
        }
        return self as NSError
    }
}
