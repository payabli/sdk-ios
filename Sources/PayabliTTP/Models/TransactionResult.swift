import Foundation

public enum SyncStatus: Sendable {
    case synced
    case pendingSyncWithBackend
}

/// Result returned to partners after a successful charge.
/// Phase 2 will add: fiservTransactionId, cardBrand, lastFour, authCode.
public struct TransactionResult: Sendable {
    public let transactionId: String
    public let syncStatus: SyncStatus
}
