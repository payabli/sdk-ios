import Foundation
import PayabliSDKCore

/// What the card-present facade reports about its own lifecycle, through its session's client.
///
/// Reports run one after another off the caller's path, so a slow send never delays the call that made it.
@MainActor
final class TapToPayReports {
    private let telemetry: TelemetryClient
    private var tail: Task<Void, Never>?

    init(telemetry: TelemetryClient) {
        self.telemetry = telemetry
    }

    func initializeStarted() {
        enqueue { await $0.emit(TelemetryEventName.ttpInitializeStarted) }
    }

    /// - Parameter duration: how long the run took.
    func initializeSucceeded(after duration: Duration) {
        let properties = ["duration_ms": Self.milliseconds(duration)]
        enqueue { await $0.emit(TelemetryEventName.ttpInitializeSucceeded, properties: properties) }
    }

    /// Reports the number the host is told, never its text, and sends at once.
    ///
    /// - Parameter failure: what the run threw, before it was translated for the host.
    /// - Parameter duration: how long the run took.
    func initializeFailed(_ failure: Error, after duration: Duration) {
        var properties = ["outcome": "failed", "duration_ms": Self.milliseconds(duration)]
        if let told = TapToPayErrorTranslation.hostError(for: failure) as? TapToPayError {
            properties["error_number"] = String(told.code)
        }
        enqueue { telemetry in
            await telemetry.emit(TelemetryEventName.ttpInitializeFailed, properties: properties)
            await telemetry.flush()
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
