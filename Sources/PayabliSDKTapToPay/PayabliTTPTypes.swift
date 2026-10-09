import Foundation

/// The session lifecycle for Tap to Pay.
///
/// A Swift enum rather than an `@objc` one, because some cases carry a value an
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

    /// The device is registered and owes its activation code, and `activationId` is the id the
    /// activation routes take. It is handed over on this state and nowhere else.
    case pendingActivation(activationId: String)

    /// The session failed, and `reason` says what a host can do about it.
    case failed(reason: PayabliTTPFailureReason)

    /// The merchant has not accepted the terms their platform requires, so the session stops here and
    /// the host presents them. Resolved the way `pendingActivation` is: the host acts, then initializes
    /// again.
    case pendingTerms

    /// A charge holds the reader, and `activity` says what it is doing. Entered
    /// when a charge starts and left when it ends; the outcome is what the charge
    /// returns or throws.
    case charging(activity: TapToPayChargeActivity)
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
    case charging = 10
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
        case .charging: return .charging
        }
    }

    /// How far the reader has got configuring, or `nil` when no configuration is
    /// running.
    var readerConfigurationPercent: Int? {
        guard case let .initializingReader(percent) = self else { return nil }
        return percent
    }

    /// What the running charge is doing, or `nil` when no charge is running.
    var chargeActivity: TapToPayChargeActivity? {
        guard case let .charging(activity) = self else { return nil }
        return activity
    }

    /// Why the session failed, or `nil` when it has not.
    var failureReason: PayabliTTPFailureReason? {
        guard case let .failed(reason) = self else { return nil }
        return reason
    }

    /// The id the device is activated under, or `nil` when no activation is owed.
    var activationId: String? {
        guard case let .pendingActivation(activationId) = self else { return nil }
        return activationId
    }
}

/// The transaction type. `.sale` is the only one.
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
