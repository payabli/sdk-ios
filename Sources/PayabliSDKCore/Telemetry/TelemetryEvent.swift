import Foundation

/// Envelope for a single telemetry event (PRD §24.3).
///
/// Schema-versioned for forward compatibility. **Contains no PII** (NFR-20).
public struct TelemetryEvent: Encodable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let sdkVersion: String
    public let timestamp: Date
    public let sessionId: String
    public let deviceIdHash: String?
    public let entry: String
    public let environment: String
    public let event: String
    public let properties: [String: String]

    public init(
        sdkVersion: String,
        sessionId: String,
        deviceIdHash: String?,
        entry: String,
        environment: String,
        event: String,
        properties: [String: String],
        timestamp: Date = Date()
    ) {
        self.schemaVersion = Self.schemaVersion
        self.sdkVersion = sdkVersion
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.deviceIdHash = deviceIdHash
        self.entry = entry
        self.environment = environment
        self.event = event
        self.properties = properties
    }
}

/// Catalog of event names emitted by the SDK (PRD §24.3).
public enum TelemetryEventName {
    // Tokenization
    public static let tokenizationStarted   = "tokenization.started"
    public static let tokenizationSucceeded = "tokenization.succeeded"
    public static let tokenizationFailed    = "tokenization.failed"
    public static let tokenizationCancelled = "tokenization.cancelled"
    public static let formPresented         = "form.presented"
    public static let formValidationError   = "form.validationError"

    // TTP lifecycle
    public static let ttpInitializeStarted     = "ttp.initialize.started"
    public static let ttpInitializeSucceeded   = "ttp.initialize.succeeded"
    public static let ttpInitializeFailed      = "ttp.initialize.failed"
    public static let ttpAttestationStarted    = "ttp.attestation.started"
    public static let ttpAttestationSucceeded  = "ttp.attestation.succeeded"
    public static let ttpAttestationFailed     = "ttp.attestation.failed"
    public static let ttpChargeStarted         = "ttp.charge.started"
    public static let ttpChargeSucceeded       = "ttp.charge.succeeded"
    public static let ttpChargeFailed          = "ttp.charge.failed"
    public static let ttpNfcStarted            = "ttp.nfc.started"
    public static let ttpNfcSucceeded          = "ttp.nfc.succeeded"
    public static let ttpNfcFailed             = "ttp.nfc.failed"
    public static let ttpReinitializeStarted   = "ttp.reinitialize.started"
    public static let ttpReinitializeSucceeded = "ttp.reinitialize.succeeded"
    public static let ttpPendingEnqueued       = "ttp.pendingUpdate.enqueued"
    public static let ttpPendingSynced         = "ttp.pendingUpdate.synced"
    public static let ttpPendingEvicted        = "ttp.pendingUpdate.evicted"
    public static let ttpStateChanged          = "ttp.session.stateChanged"

    // System
    public static let sdkInitialized     = "sdk.initialized"
    public static let telemetryDisabled  = "sdk.telemetryDisabled"
    public static let authTokenAcquired  = "auth.tokenAcquired"
    public static let authTokenFailed    = "auth.tokenFailed"
    public static let authTokenRefreshed = "auth.tokenRefreshed"
}
