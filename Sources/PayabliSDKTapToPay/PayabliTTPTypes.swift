import Foundation

/// The 9-state session lifecycle for Tap to Pay (PRD §17).
@objc public enum PayabliTTPSessionState: Int, Sendable {
    case idle = 0
    case attestingDevice = 1
    case fetchingConfig = 2
    case initializingReader = 3
    case ready = 4
    case sessionExpired = 5
    case reinitializing = 6
    case pendingActivation = 7
    case error = 8
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
