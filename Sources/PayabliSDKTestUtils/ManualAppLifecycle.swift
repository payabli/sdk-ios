import Foundation
import PayabliSDKCore

/// An app lifecycle the test moves to the background by hand.
///
/// The stream exists from construction, so a backgrounding made before delivery starts listening is kept.
package final class ManualAppLifecycle: AppLifecycle, @unchecked Sendable {
    private let lock = NSLock()
    private let stream: AsyncStream<BackgroundWindow>
    private let continuation: AsyncStream<BackgroundWindow>.Continuation
    private var closed = 0

    package init() {
        (stream, continuation) = AsyncStream.makeStream(of: BackgroundWindow.self)
    }

    /// How many windows delivery has closed.
    package var closedCount: Int {
        lock.withLock { closed }
    }

    /// Moves the app to the background, and returns once delivery closes that backgrounding's window.
    ///
    /// - Returns: `false` when the window was not closed within two seconds.
    @discardableResult
    package func background() async -> Bool {
        let closedOrTimedOut = Once()
        let window = BackgroundWindow { [self] in
            lock.withLock { closed += 1 }
            closedOrTimedOut.settle(true)
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            closedOrTimedOut.settle(false)
        }
        continuation.yield(window)
        return await closedOrTimedOut.value()
    }

    package func backgroundings() -> AsyncStream<BackgroundWindow> {
        stream
    }
}

/// A result settled by whichever of two parties answers first.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var waiter: CheckedContinuation<Bool, Never>?

    func settle(_ value: Bool) {
        let resume: CheckedContinuation<Bool, Never>? = lock.withLock {
            guard result == nil else { return nil }
            result = value
            defer { waiter = nil }
            return waiter
        }
        resume?.resume(returning: value)
    }

    func value() async -> Bool {
        await withCheckedContinuation { continuation in
            let settled: Bool? = lock.withLock {
                if let result {
                    return result
                }
                waiter = continuation
                return nil
            }
            if let settled {
                continuation.resume(returning: settled)
            }
        }
    }
}
