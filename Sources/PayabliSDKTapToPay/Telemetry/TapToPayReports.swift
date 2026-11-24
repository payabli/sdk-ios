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
            properties[TelemetryProperty.failureType.rawValue] = Self.failureType(of: error)
            if let code = told?.rawCode {
                properties[TelemetryProperty.code.rawValue] = code
            }
        }
        record(name, properties: properties, occurredAt: now)
    }

    func reinitializeStarted() {
        let now = Date()
        record(TelemetryEventName.ttpReinitializeStarted, occurredAt: now)
    }

    /// - Parameter duration: how long the re-arm took.
    func reinitializeSucceeded(after duration: Duration) {
        let now = Date()
        let properties = [TelemetryProperty.durationMs.rawValue: Self.milliseconds(duration)]
        record(TelemetryEventName.ttpReinitializeSucceeded, properties: properties, occurredAt: now)
    }

    /// Reports a move of the session, saying why only when it moved to failed.
    ///
    /// - Parameter from: the state the session left.
    /// - Parameter to: the state it entered.
    func sessionStateChanged(from: PayabliTTPSessionState, to: PayabliTTPSessionState) {
        let now = Date()
        var properties = [TelemetryProperty.from.rawValue: from.diagnosticName, TelemetryProperty.to.rawValue: to.diagnosticName]
        if case let .failed(reason) = to {
            properties[TelemetryProperty.reason.rawValue] = reason.diagnosticName
        }
        record(TelemetryEventName.ttpStateChanged, properties: properties, occurredAt: now)
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

    /// Which call sent a close: the charge that read the card, or `closeCapturedCharge`.
    enum CloseOrigin: String {
        case charge
        case retry
    }

    /// - Parameter origin: the call sending the close.
    func closeStarted(_ origin: CloseOrigin) {
        let now = Date()
        let properties = [TelemetryProperty.origin.rawValue: origin.rawValue]
        record(TelemetryEventName.ttpCloseStarted, properties: properties, occurredAt: now)
    }

    /// - Parameter origin: the call that sent the close.
    /// - Parameter duration: how long the close took.
    func closeSucceeded(_ origin: CloseOrigin, after duration: Duration) {
        let now = Date()
        let properties = [
            TelemetryProperty.origin.rawValue: origin.rawValue,
            TelemetryProperty.durationMs.rawValue: Self.milliseconds(duration)
        ]
        record(TelemetryEventName.ttpCloseSucceeded, properties: properties, occurredAt: now)
    }

    /// Reports a close that was not confirmed, by what the host is told. A close records an outcome rather than asking
    /// for one, so its failure is never a decline.
    ///
    /// - Parameter error: what the close failed with, before it was translated for the host.
    /// - Parameter origin: the call that sent the close.
    /// - Parameter capture: what the host is told about the money.
    /// - Parameter processorHasNoRecord: whether the refusal says the processor holds no record of the payment.
    /// - Parameter type: the catalog entry whose number this reports: the close's own for a charge's close, and the one
    ///   the host is told for `closeCapturedCharge`.
    /// - Parameter duration: how long the close took.
    func closeFailed(
        _ error: Error,
        origin: CloseOrigin,
        capture: PayabliTTPCapture,
        processorHasNoRecord: Bool,
        type: PayabliErrorType,
        after duration: Duration
    ) {
        let now = Date()
        let answer = TapToPayErrorTranslation.answer(of: error)
        var properties = [
            TelemetryProperty.outcome.rawValue: "failed",
            TelemetryProperty.durationMs.rawValue: Self.milliseconds(duration),
            TelemetryProperty.errorNumber.rawValue: String(type.number),
            TelemetryProperty.origin.rawValue: origin.rawValue,
            TelemetryProperty.failureType.rawValue: Self.failureType(of: error),
            TelemetryProperty.capture.rawValue: Self.spelled(capture)
        ]
        properties[TelemetryProperty.code.rawValue] = answer.rawCode
        properties[TelemetryProperty.httpStatus.rawValue] = answer.httpStatus.map(String.init)
        if processorHasNoRecord {
            properties[TelemetryProperty.reason.rawValue] = "processor_no_record"
        }
        record(TelemetryEventName.ttpCloseFailed, properties: properties, occurredAt: now)
    }

    private func record(_ name: String, properties: [String: String] = [:], occurredAt: Date) {
        TelemetryRecorders.recordFor(session, name, properties: properties, occurredAt: occurredAt)
    }

    /// The simple name of the type an operation raised, read through a redaction to the type it stands in for; never a message.
    ///
    /// - Parameter error: what the operation threw, before it was translated for the host.
    /// - Returns: the redacted type's name, or the thrown type's otherwise.
    static func failureType(of error: any Error) -> String {
        if let redacted = (error as? TapToPayError)?.underlying as? RedactedCause {
            return redacted.simpleTypeName
        }
        if let redacted = (error as? PayabliGenericError)?.underlying as? RedactedCause {
            return redacted.simpleTypeName
        }
        return RedactedCause(error).simpleTypeName
    }

    private static func spelled(_ capture: PayabliTTPCapture) -> String {
        switch capture {
        case .notCharged: "not_charged"
        case .unknown: "unknown"
        case .charged: "charged"
        }
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}
