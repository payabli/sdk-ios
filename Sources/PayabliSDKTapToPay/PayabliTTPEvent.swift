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
