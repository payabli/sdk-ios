import Foundation
import PayabliSDKCore

/// What the card-present facade reports about its own lifecycle, as belonging to the session it runs on.
///
/// Each report is stamped with the time it is made.
@MainActor
final class TapToPayReports {
    private let session: TelemetrySessionContext

    /// - Parameter session: the session the facade runs on, which every report carries.
    init(session: TelemetrySessionContext) {
        self.session = session
    }

    func initializeStarted() {
        let now = Date()
        record(TelemetryEventName.ttpInitializeStarted, occurredAt: now)
    }

    /// - Parameter duration: how long the run took.
    func initializeSucceeded(after duration: Duration) {
        let now = Date()
        let properties = [TelemetryProperty.durationMs.rawValue: Self.milliseconds(duration)]
        record(TelemetryEventName.ttpInitializeSucceeded, properties: properties, occurredAt: now)
    }

    /// Reports a run that ended without a reader, by what the host is told and never by its text.
    ///
    /// A dismissed setup sheet is a cancel and a setup waiting on a person is pending, neither a failure.
    ///
    /// - Parameter error: what the run threw, before it was translated for the host.
    /// - Parameter duration: how long the run took.
    func initializeEnded(_ error: Error, after duration: Duration) {
        let now = Date()
        let told = TapToPayErrorTranslation.hostError(for: error) as? TapToPayError
        var properties = [TelemetryProperty.durationMs.rawValue: Self.milliseconds(duration)]
        let name: String
        switch told?.type {
        case .userCancelled:
            name = TelemetryEventName.ttpInitializeCancelled
        case .devicePendingActivation:
            name = TelemetryEventName.ttpInitializePending
            properties[TelemetryProperty.state.rawValue] = "pending_activation"
        case .termsNotAccepted:
            name = TelemetryEventName.ttpInitializePending
            properties[TelemetryProperty.state.rawValue] = "pending_terms"
        default:
            name = TelemetryEventName.ttpInitializeFailed
            properties[TelemetryProperty.outcome.rawValue] = "failed"
            if let told {
                properties[TelemetryProperty.errorNumber.rawValue] = String(told.code)
            }
        }
        record(name, properties: properties, occurredAt: now)
    }

    func attestationStarted() {
        let now = Date()
        record(TelemetryEventName.ttpAttestationStarted, occurredAt: now)
    }

    /// - Parameter duration: how long the attestation took.
    func attestationSucceeded(after duration: Duration) {
        let now = Date()
        let properties = [TelemetryProperty.durationMs.rawValue: Self.milliseconds(duration)]
        record(TelemetryEventName.ttpAttestationSucceeded, properties: properties, occurredAt: now)
    }

    /// Reports an attestation that was refused, by the number the host is told, and sends it at once.
    ///
    /// - Parameter error: what the attestation threw, before it was translated for the host.
    /// - Parameter duration: how long the attestation took.
    func attestationFailed(_ error: Error, after duration: Duration) {
        let now = Date()
        var properties = [TelemetryProperty.durationMs.rawValue: Self.milliseconds(duration), TelemetryProperty.outcome.rawValue: "failed"]
        if let told = TapToPayErrorTranslation.hostError(for: error) as? any PayabliError {
            properties[TelemetryProperty.errorNumber.rawValue] = String(told.code)
        }
        record(TelemetryEventName.ttpAttestationFailed, properties: properties, occurredAt: now)
    }

    private func record(_ name: String, properties: [String: String] = [:], occurredAt: Date) {
        TelemetryRecorders.recordFor(session, name, properties: properties, occurredAt: occurredAt)
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}
