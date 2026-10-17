import Foundation

/// Serialises the operations that move a card-present session, across every `PayabliTTP` in the process,
/// because the device has one card reader and one read at a time.
@MainActor
final class SessionSetupGate {
    static let shared = SessionSetupGate()

    /// An operation in the gate. `task` is what a later caller waits on or joins, and only the operation with
    /// the `id` in a slot clears that slot.
    private struct Holder {
        let kind: SessionSetupKind
        let owner: ObjectIdentifier
        let task: Task<Void, Error>
        let id: Int
    }

    /// The operation that claimed the gate last, which the next caller chains behind.
    private var last: Holder?
    /// Each `PayabliTTP`'s newest setup that has not finished, which its next caller of the same kind joins.
    private var setups: [ObjectIdentifier: Holder] = [:]
    private var nextID = 0

    /// Bumped every time any `PayabliTTP` prepares a reader. A charge captures it before the tap, so a failure
    /// that arrives after the reader was prepared again is not attributed to the new one.
    var readerGeneration = 0

    /// True from the moment a charge claims the gate until it returns, whether it is running, waiting for
    /// the operation before it, or has setups queued behind it.
    private(set) var isHeldByCharge = false

    /// Runs `work` once every operation already in the gate has finished, or joins the setup of the same kind
    /// that `owner` already has in flight.
    ///
    /// - Parameters:
    ///   - kind: Which setup this is; a later call of the same kind from `owner` joins it while it runs.
    ///   - owner: The `PayabliTTP` calling. Only its own calls join this setup; any other caller waits for it.
    ///   - work: The setup, run in a task no caller owns, so a cancelled caller does not stop it.
    func run(
        _ kind: SessionSetupKind,
        for owner: ObjectIdentifier,
        _ work: @escaping @MainActor () async throws -> Void
    ) async throws {
        if let existing = setups[owner], existing.kind == kind {
            return try await existing.task.value
        }

        // Chains behind the operation holding the gate. Re-checking in a loop
        // re-awaits a task that has already finished and spins the main actor
        // until the slot is cleared, starving everything else on it.
        let previous = last?.task
        let id = claimID()

        let task = Task<Void, Error> { @MainActor in
            // Its failure belongs to its own caller.
            if let previous {
                _ = try? await previous.value
            }
            try await work()
        }
        let holder = Holder(kind: kind, owner: owner, task: task, id: id)
        last = holder
        setups[owner] = holder
        defer {
            release(id)
            if setups[owner]?.id == id {
                setups[owner] = nil
            }
        }
        try await task.value
    }

    /// Holds the gate for a charge until `body` returns. `body` runs in the caller's task, so cancelling the
    /// charge reaches it.
    ///
    /// - Parameters:
    ///   - owner: The `PayabliTTP` charging.
    ///   - body: The charge, run in the caller's task once every operation already in the gate has finished.
    /// - Returns: The charge's result.
    func holdForCharge<T>(for owner: ObjectIdentifier, _ body: @MainActor () async throws -> T) async throws -> T {
        // Claimed before the first suspension, so a setup call made while the
        // charge waits for the previous one chains behind the charge.
        let previous = last?.task
        let id = claimID()
        let (released, release) = AsyncStream<Void>.makeStream()
        let hold = Task<Void, Error> { @MainActor in
            // Ends when the charge finishes the stream; nothing is ever yielded.
            var waiting = released.makeAsyncIterator()
            _ = await waiting.next()
        }
        last = Holder(kind: .charge, owner: owner, task: hold, id: id)
        isHeldByCharge = true
        defer {
            isHeldByCharge = false
            release.finish()
            self.release(id)
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
