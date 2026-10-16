import Foundation
import PayabliSDKCore

/// What the card-present facade reports about its own lifecycle, through its session's client.
///
/// Reports run one after another off the caller's path, so a slow send never delays the call that made it.
/// Each is stamped when it is made, so one queued behind a slow send keeps the time it happened.
@MainActor
final class TapToPayReports {
    private let telemetry: TelemetryClient
    private var tail: Task<Void, Never>?

    init(telemetry: TelemetryClient) {
        self.telemetry = telemetry
    }

    func initializeStarted() {
        let now = Date()
        enqueue { await $0.emit(TelemetryEventName.ttpInitializeStarted, occurredAt: now) }
    }

    /// - Parameter duration: how long the run took.
    func initializeSucceeded(after duration: Duration) {
        let now = Date()
        let properties = ["duration_ms": Self.milliseconds(duration)]
        enqueue { await $0.emit(TelemetryEventName.ttpInitializeSucceeded, properties: properties, occurredAt: now) }
    }

    /// Reports a run that ended without a reader, by what the host is told and never by its text.
    ///
    /// A dismissed setup sheet is a cancel and a setup waiting on a person is pending, neither a failure.
    /// A cancel or a failure is sent at once; a pending setup waits for the batch.
    ///
    /// - Parameter error: what the run threw, before it was translated for the host.
    /// - Parameter duration: how long the run took.
    func initializeEnded(_ error: Error, after duration: Duration) {
        let now = Date()
        let told = TapToPayErrorTranslation.hostError(for: error) as? TapToPayError
        var properties = ["duration_ms": Self.milliseconds(duration)]
        let name: String
        var sendsAtOnce = true
        switch told?.type {
        case .userCancelled:
            name = TelemetryEventName.ttpInitializeCancelled
        case .devicePendingActivation:
            name = TelemetryEventName.ttpInitializePending
            properties["state"] = "pending_activation"
            sendsAtOnce = false
        case .termsNotAccepted:
            name = TelemetryEventName.ttpInitializePending
            properties["state"] = "pending_terms"
            sendsAtOnce = false
        default:
            name = TelemetryEventName.ttpInitializeFailed
            properties["outcome"] = "failed"
            if let told {
                properties["error_number"] = String(told.code)
            }
        }
        enqueue { [properties, sendsAtOnce] telemetry in
            await telemetry.emit(name, properties: properties, occurredAt: now)
            if sendsAtOnce {
                await telemetry.flush()
            }
        }
    }

    /// Waits until every report made so far has reached the client.
    func sent() async {
        await tail?.value
    }

    private func enqueue(_ report: @escaping @Sendable (TelemetryClient) async -> Void) {
        let previous = tail
        let telemetry = telemetry
        tail = Task {
            await previous?.value
            await report(telemetry)
        }
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}
