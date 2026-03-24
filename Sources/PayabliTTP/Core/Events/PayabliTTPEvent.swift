import Foundation

/// Domain events emitted by the SDK during its lifecycle.
/// Partners can observe these via PayabliTTP.events (AsyncStream).
public enum PayabliTTPEvent: Sendable {

    // MARK: - Initialization lifecycle
    case attestationStarted
    case attestationCompleted
    case configFetched
    case readerInitializing
    case sessionReady

    // MARK: - Transaction lifecycle
    case transactionInitiated(paymentTransId: String)
    case waitingForCardTap
    case cardTapCompleted
    /// The NFC charge completed. `syncStatus` indicates whether the Payabli backend
    /// was successfully updated (`.synced`) or the update is queued for the next session
    /// (`.pendingSyncWithBackend`). Partners should check `syncStatus` rather than
    /// treating every `transactionCompleted` event as a confirmed backend sync.
    case transactionCompleted(paymentTransId: String, syncStatus: SyncStatus)
    case transactionFailed(error: String)

    // MARK: - Session management
    case sessionExpired
    case reinitializationStarted
    case reinitializationCompleted

    // MARK: - Error recovery
    case pendingUpdateQueued(paymentTransId: String)
    case pendingUpdateRetried(paymentTransId: String)
    case pendingUpdateSynced(paymentTransId: String)
}
