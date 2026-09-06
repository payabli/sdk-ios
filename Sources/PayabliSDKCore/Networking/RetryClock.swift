import Foundation

/// The passage of time as `Retry` sees it.
///
/// A seam rather than a direct `Task.sleep`, because every assertion about a backoff schedule or a total
/// budget is otherwise either a real wait or vacuous: a test that sets the delays to zero to stay fast
/// proves nothing about the arithmetic that produced them.
package protocol RetryClock: Sendable {
    /// Seconds since an arbitrary origin fixed at creation. Monotonic.
    func elapsed() -> TimeInterval

    func sleep(for seconds: TimeInterval) async throws
}

/// The shipping clock.
///
/// `ContinuousClock` rather than a wall clock or `DispatchTime`: it keeps advancing while the device is
/// asleep and is unaffected by a clock correction, so a budget cannot be extended by the device dozing or
/// cut short by the time changing underneath it.
package struct SystemRetryClock: RetryClock {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    package init() {
        origin = ContinuousClock().now
    }

    package func elapsed() -> TimeInterval {
        let components = (clock.now - origin).components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }

    package func sleep(for seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await clock.sleep(for: .seconds(seconds))
    }
}
