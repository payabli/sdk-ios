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

/// Sync status on a `TransactionResult` indicating whether the backend update
/// succeeded or was enqueued for later sync.
@objc public enum SyncStatus: Int, Sendable {
    case synced = 0
    case pendingSyncWithBackend = 1
}

/// Result of a successful `charge()` call.
public struct TransactionResult: Sendable {
    public let paymentTransId: String
    public let syncStatus: SyncStatus

    public init(paymentTransId: String, syncStatus: SyncStatus) {
        self.paymentTransId = paymentTransId
        self.syncStatus = syncStatus
    }
}

/// Pending update awaiting backend sync (PRD §21.2).
public struct PendingUpdate: Codable, Sendable {
    public let paymentTransId: String
    public let updateBody: Data       // opaque JSON body (forward-compatible)
    public let createdAt: Date
    public let attemptCount: Int

    public init(paymentTransId: String, updateBody: Data, createdAt: Date = Date(), attemptCount: Int = 0) {
        self.paymentTransId = paymentTransId
        self.updateBody = updateBody
        self.createdAt = createdAt
        self.attemptCount = attemptCount
    }
}
