import Foundation

/// Serialises the operations that move a card-present session, across every `PayabliTTP` in the process,
/// because the device has one card reader and one read at a time.
@MainActor
final class SessionSetupGate {
    static let shared = SessionSetupGate()

    /// An operation's place in the gate: `task` is what a later caller waits on or joins, and only the
    /// operation whose `id` is in a slot clears that slot.
    private struct Claim {
        let task: Task<Void, Error>
        let id: Int
    }

    /// A setup a later call of the same `kind`, from the same `PayabliTTP`, joins.
    private struct Setup {
        let kind: SessionSetupKind
        let claim: Claim
    }

    /// The operation that claimed the gate last, which the next caller chains behind.
    private var last: Claim?
    /// Each `PayabliTTP`'s newest setup, until the call that started it returns or a charge claims the gate.
    private var setups: [ObjectIdentifier: Setup] = [:]
    private var nextID = 0

    /// Bumped every time any `PayabliTTP` prepares a reader. A charge captures it before the tap, so a failure
    /// that arrives after the reader was prepared again is not attributed to the new one.
    var readerGeneration = 0

    /// True from the moment a charge claims the gate until it returns, whether it is running, waiting for
    /// the operation before it, or has setups queued behind it.
    private(set) var isHeldByCharge = false

    /// Runs `work` after every operation already in the gate, or joins `owner`'s pending setup of this `kind`.
    ///
    /// - Parameters:
    ///   - kind: Which setup this is; `owner`'s next call of the same kind joins it until a charge claims the gate.
    ///   - owner: The `PayabliTTP` calling. Only its own calls join this setup; any other caller waits for it.
    ///   - work: The setup, run in a task no caller owns, so a cancelled caller does not stop it.
    func run(
        _ kind: SessionSetupKind,
        for owner: ObjectIdentifier,
        _ work: @escaping @MainActor () async throws -> Void
    ) async throws {
        if let existing = setups[owner], existing.kind == kind {
            return try await existing.claim.task.value
        }

        // Chains behind the operation that claimed the gate last. Re-checking in
        // a loop re-awaits a task that has already finished and spins the main
        // actor until the slot is cleared, starving everything else on it.
        let previous = last?.task
        let claim = Claim(
            task: Task<Void, Error> { @MainActor in
                // Its failure belongs to its own caller.
                if let previous {
                    _ = try? await previous.value
                }
                try await work()
            },
            id: claimID()
        )
        last = claim
        setups[owner] = Setup(kind: kind, claim: claim)
        defer {
            release(claim.id)
            if setups[owner]?.claim.id == claim.id {
                setups[owner] = nil
            }
        }
        try await claim.task.value
    }

    /// Holds the gate for a charge until `body` returns. `body` runs in the caller's task, so cancelling the
    /// charge reaches it.
    ///
    /// - Parameter body: The charge, run in the caller's task once every operation already in the gate has
    ///   finished.
    /// - Returns: The charge's result.
    func holdForCharge<T>(_ body: @MainActor () async throws -> T) async throws -> T {
        // Claimed before the first suspension, so a setup call made while the
        // charge waits for the previous one chains behind the charge.
        let previous = last?.task
        let (released, release) = AsyncStream<Void>.makeStream()
        let claim = Claim(
            task: Task<Void, Error> { @MainActor in
                // Ends when the charge finishes the stream; nothing is ever yielded.
                var waiting = released.makeAsyncIterator()
                _ = await waiting.next()
            },
            id: claimID()
        )
        last = claim
        // A setup call made from here on waits for this charge, so no earlier setup can be joined.
        setups.removeAll()
        isHeldByCharge = true
        defer {
            isHeldByCharge = false
            release.finish()
            self.release(claim.id)
        }

        if let previous {
            _ = try? await previous.value
        }
        return try await body()
    }

    private func claimID() -> Int {
        nextID += 1
        return nextID
    }

    /// Clears the last claim only while `id` still holds it, so an operation that chained behind keeps its claim.
    private func release(_ id: Int) {
        if last?.id == id {
            last = nil
        }
    }
}
