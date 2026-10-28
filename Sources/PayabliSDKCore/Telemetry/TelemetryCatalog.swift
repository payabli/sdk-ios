/// A property key an event may carry, spelled as it goes on the wire.
package enum TelemetryProperty: String, CaseIterable, Sendable {
    case outcome
    case code
    case reason
    case durationMs = "duration_ms"
    case attempt
    case state
    case from
    case to
    case step
    case field
    case origin
    case method
    case errorNumber = "error_number"
    case failureType = "failure_type"
    /// How many events the queue evicted, as text.
    case dropped
}

/// Which property keys each event may carry, and the gate that holds an event to it.
///
/// Deny by default, applied before an event is queued: an event this table does not name is dropped whole, and a key
/// an event does not declare is dropped from it, so nothing unvetted is held in memory waiting for a send.
package enum TelemetryCatalog {
    /// Longest property key that may be reported.
    static let maxKeyLength = 64

    /// Longest property value that may be reported.
    static let maxValueLength = 256

    /// Most properties one event may carry.
    static let maxProperties = 20

    private static let timed: Set<TelemetryProperty> = [.durationMs]

    private static let failed: Set<TelemetryProperty> = [.outcome, .code, .errorNumber, .durationMs, .failureType]

    private static let payIn: Set<TelemetryProperty> = failed.union([.origin])

    private static let allowed: [String: Set<TelemetryProperty>] = [
        TelemetryEventName.payinCaptureCompleted: payIn.union([.method]),
        TelemetryEventName.payinAuthorizeCompleted: payIn.union([.method]),
        TelemetryEventName.payinStoreMethodCompleted: payIn.union([.method]),
        TelemetryEventName.payinVoidCompleted: payIn,
        TelemetryEventName.payinReadCompleted: payIn,
        TelemetryEventName.formPresented: [.step],
        TelemetryEventName.formValidationError: [.reason, .field],
        TelemetryEventName.ttpInitializeStarted: [],
        TelemetryEventName.ttpInitializeSucceeded: timed,
        TelemetryEventName.ttpInitializeFailed: failed,
        TelemetryEventName.ttpInitializeCancelled: timed,
        TelemetryEventName.ttpInitializePending: [.state, .durationMs],
        TelemetryEventName.ttpAttestationStarted: [],
        TelemetryEventName.ttpAttestationSucceeded: timed,
        TelemetryEventName.ttpAttestationFailed: [.outcome, .errorNumber, .durationMs, .code],
        TelemetryEventName.ttpAttestationQuotaExhausted: [.code, .reason],
        TelemetryEventName.ttpChargeStarted: [],
        TelemetryEventName.ttpChargeSucceeded: timed,
        TelemetryEventName.ttpChargeFailed: failed,
        TelemetryEventName.ttpNfcStarted: [],
        TelemetryEventName.ttpNfcSucceeded: timed,
        TelemetryEventName.ttpNfcFailed: [.outcome, .reason, .code, .errorNumber, .durationMs],
        TelemetryEventName.ttpCloseFailed: failed.union([.origin]),
        TelemetryEventName.ttpReinitializeStarted: [],
        TelemetryEventName.ttpReinitializeSucceeded: timed,
        TelemetryEventName.ttpStateChanged: [.from, .to, .reason],
        TelemetryEventName.sdkInitialized: [.state],
        TelemetryEventName.sdkInitializeStarted: [.state],
        TelemetryEventName.sdkInitializeFailed: failed.union([.reason]),
        TelemetryEventName.sdkTelemetryOverflow: [.dropped],
        TelemetryEventName.authTokenAcquired: timed,
        TelemetryEventName.authTokenFailed: [.outcome, .reason, .durationMs, .failureType],
        TelemetryEventName.authTokenRefreshed: [.durationMs, .attempt]
    ]

    /// Every event this catalog reports, with the keys each may carry.
    static var events: [String: Set<TelemetryProperty>] {
        allowed
    }

    /// Reduces properties to what an event may report.
    ///
    /// A pair is dropped rather than corrected: a value that is empty, too long or outside printable ASCII is one the
    /// SDK did not mean to send, and truncating it would keep a record that no longer says what the caller meant.
    ///
    /// - Parameter name: the event's catalog name.
    /// - Parameter properties: the properties as the caller assembled them.
    /// - Returns: the properties the event may report, or `nil` when the catalog does not name the event.
    package static func scrub(_ name: String, _ properties: [String: String]) -> [String: String]? {
        guard let keys = allowed[name] else { return nil }
        return reduce(properties, to: Set(keys.map(\.rawValue)))
    }

    /// Keeps the pairs whose key is declared and whose key and value may be reported, at most `maxProperties` of
    /// them, the first by key.
    ///
    /// - Parameter properties: the properties as the caller assembled them.
    /// - Parameter keys: the keys the event declares.
    /// - Returns: the pairs that may be reported.
    static func reduce(_ properties: [String: String], to keys: Set<String>) -> [String: String] {
        let reportable = properties
            .filter { key, value in keys.contains(key) && key.count <= maxKeyLength && isReportable(value) }
            .sorted { $0.key < $1.key }
            .prefix(maxProperties)
        return Dictionary(uniqueKeysWithValues: reportable.map { ($0.key, $0.value) })
    }

    private static func isReportable(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= maxValueLength
            && value.unicodeScalars.allSatisfy { (0x20 ... 0x7E).contains($0.value) }
    }
}
