import Foundation

/// The session lifecycle for Tap to Pay (PRD §17).
///
/// A Swift enum rather than an `@objc` one, because two cases carry a value an
/// `Int`-backed enum cannot hold. ``PayabliTTPSessionStateCode`` is the
/// projection the bridges read.
public enum PayabliTTPSessionState: Sendable, Equatable {
    case idle
    case attestingDevice
    case fetchingConfig

    /// The reader is being configured, and `percent` is how far it has got, or
    /// `nil` before it has reported.
    ///
    /// The percentage lives here so it cannot exist outside the phase it
    /// describes. Configuration runs for minutes on a device arming for the
    /// first time.
    case initializingReader(percent: Int?)

    case ready
    case sessionExpired
    case reinitializing
    case pendingActivation

    /// The session failed, and `reason` says what a host can do about it.
    case failed(reason: PayabliTTPFailureReason)

    /// The merchant has not accepted the terms their platform requires, so the session stops here and
    /// the host presents them. Resolved the way `pendingActivation` is: the host acts, then initializes
    /// again.
    case pendingTerms
}

/// ``PayabliTTPSessionState`` without its payloads, for ObjC, MAUI, React
/// Native and Flutter, which cannot express an enum that carries one.
///
/// Raw values are public API: do not reorder or renumber. A host reads the
/// payloads through `PayabliTTP`'s own accessors.
@objc public enum PayabliTTPSessionStateCode: Int, Sendable {
    case idle = 0
    case attestingDevice = 1
    case fetchingConfig = 2
    case initializingReader = 3
    case ready = 4
    case sessionExpired = 5
    case reinitializing = 6
    case pendingActivation = 7
    case failed = 8
    case pendingTerms = 9
}

public extension PayabliTTPSessionState {
    /// This state without its payload.
    var code: PayabliTTPSessionStateCode {
        switch self {
        case .idle: return .idle
        case .attestingDevice: return .attestingDevice
        case .fetchingConfig: return .fetchingConfig
        case .initializingReader: return .initializingReader
        case .ready: return .ready
        case .sessionExpired: return .sessionExpired
        case .reinitializing: return .reinitializing
        case .pendingActivation: return .pendingActivation
        case .failed: return .failed
        case .pendingTerms: return .pendingTerms
        }
    }

    /// How far the reader has got configuring, or `nil` when no configuration is
    /// running.
    var readerConfigurationPercent: Int? {
        guard case let .initializingReader(percent) = self else { return nil }
        return percent
    }

    /// Why the session failed, or `nil` when it has not.
    var failureReason: PayabliTTPFailureReason? {
        guard case let .failed(reason) = self else { return nil }
        return reason
    }
}

/// TTP transaction type. v1.0 supports `.sale` only (PRD FR-11D.1).
@objc public enum PayabliTTPPaymentType: Int, Sendable {
    case sale = 0
}

/// Result of a successful `charge()` call.
public struct TransactionResult: Sendable {
    public let paymentTransId: String

    public init(paymentTransId: String) {
        self.paymentTransId = paymentTransId
    }
}
