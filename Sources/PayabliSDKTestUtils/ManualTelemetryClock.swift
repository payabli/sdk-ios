import Foundation
import PayabliSDKCore

/// A telemetry timer that waits until the test says it has fired.
package actor ManualTelemetryClock {
    private var sleeper: CheckedContinuation<Void, Error>?
    private var sleepingWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    package init() {}

    /// The wait to hand a `TelemetryClient`.
    package nonisolated var sleep: TelemetryClient.Sleep {
        { [self] _ in try await wait() }
    }

    /// Fires the timer once, and returns after the timer has acted on it and is waiting again.
    ///
    /// - Returns: `false` when no timer was waiting, or none waited again, within two seconds.
    @discardableResult
    package func tick() async -> Bool {
        guard await untilSleeping() else { return false }
        sleeper?.resume()
        sleeper = nil
        return await untilSleeping()
    }

    private func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleeper = continuation
                let waiters = sleepingWaiters
                sleepingWaiters.removeAll()
                waiters.values.forEach { $0.resume(returning: true) }
            }
        } onCancel: {
            Task { await self.cancelSleeper() }
        }
    }

    private func cancelSleeper() {
        sleeper?.resume(throwing: CancellationError())
        sleeper = nil
    }

    private func untilSleeping() async -> Bool {
        guard sleeper == nil else { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            sleepingWaiters[id] = continuation
            Task {
                try? await Task.sleep(for: .seconds(2))
                self.giveUp(id)
            }
        }
    }

    private func giveUp(_ id: UUID) {
        sleepingWaiters.removeValue(forKey: id)?.resume(returning: false)
    }
}
