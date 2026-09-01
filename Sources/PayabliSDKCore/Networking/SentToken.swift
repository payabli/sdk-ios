import Foundation

/// Carries the token the chain stamped to the layer that reports a rejection.
///
/// The chain reads the token after that layer does, so the two can disagree under a rotation.
/// Reporting the earlier read names a credential the service did not refuse.
///
/// One instance per attempt, bound as a task-local. Concurrent requests each bind their own.
final class SentToken: @unchecked Sendable {
    @TaskLocal static var current: SentToken?

    private let lock = NSLock()
    private var stored: String?

    /// Nil means nothing stamped, which means the chain did not run.
    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ token: String) {
        lock.lock()
        defer { lock.unlock() }
        stored = token
    }
}
