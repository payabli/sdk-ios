import Foundation

/// Envelope for a single telemetry event.
///
/// Schema-versioned for forward compatibility. **Contains no PII**.
package struct TelemetryEvent: Encodable, Sendable {
    package static let schemaVersion = 1

    package let schemaVersion: Int
    package let sdkVersion: String
    package let timestamp: Date
    package let sessionId: String
    package let deviceIdHash: String?
    package let entry: String
    package let environment: String
    package let event: String
    package let properties: [String: String]

    package init(
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

    /// The same event with the device's identifier set.
    ///
    /// - Parameter deviceIdHash: the identifier, or `nil` when the device cannot be identified.
    /// - Returns: the event carrying it.
    package func carrying(deviceIdHash: String?) -> TelemetryEvent {
        TelemetryEvent(
            sdkVersion: sdkVersion,
            sessionId: sessionId,
            deviceIdHash: deviceIdHash,
            entry: entry,
            environment: environment,
            event: event,
            properties: properties,
            timestamp: timestamp
        )
    }
}

/// Catalog of event names emitted by the SDK.
package enum TelemetryEventName {
    // Card-not-present operations
    package static let payinCaptureCompleted = "payin.capture.completed"
    package static let payinAuthorizeCompleted = "payin.authorize.completed"
    package static let payinStoreMethodCompleted = "payin.storeMethod.completed"
    package static let payinVoidCompleted = "payin.void.completed"
    package static let payinReadCompleted = "payin.read.completed"

    // Form
    package static let formPresented = "form.presented"
    package static let formValidationError = "form.validationError"

    // TTP lifecycle
    package static let ttpInitializeStarted = "ttp.initialize.started"
    package static let ttpInitializeSucceeded = "ttp.initialize.succeeded"
    package static let ttpInitializeFailed = "ttp.initialize.failed"
    package static let ttpAttestationStarted = "ttp.attestation.started"
    package static let ttpAttestationSucceeded = "ttp.attestation.succeeded"
    package static let ttpAttestationFailed = "ttp.attestation.failed"
    package static let ttpAttestationQuotaExhausted = "ttp.attestation.quotaExhausted"
    package static let ttpChargeStarted = "ttp.charge.started"
    package static let ttpChargeSucceeded = "ttp.charge.succeeded"
    package static let ttpChargeFailed = "ttp.charge.failed"
    package static let ttpNfcStarted = "ttp.nfc.started"
    package static let ttpNfcSucceeded = "ttp.nfc.succeeded"
    package static let ttpNfcFailed = "ttp.nfc.failed"
    package static let ttpCloseFailed = "ttp.close.failed"
    package static let ttpReinitializeStarted = "ttp.reinitialize.started"
    package static let ttpReinitializeSucceeded = "ttp.reinitialize.succeeded"
    package static let ttpStateChanged = "ttp.session.stateChanged"

    // System
    package static let sdkInitialized = "sdk.initialized"
    package static let sdkInitializeStarted = "sdk.initialize.started"
    package static let sdkInitializeFailed = "sdk.initialize.failed"
    package static let authTokenAcquired = "auth.tokenAcquired"
    package static let authTokenFailed = "auth.tokenFailed"
    package static let authTokenRefreshed = "auth.tokenRefreshed"
}

package extension TelemetryEventName {
    static let ttpInitializeCancelled = "ttp.initialize.cancelled"
    static let ttpInitializePending = "ttp.initialize.pending"
}
