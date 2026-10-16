import Foundation

/// Serialises the operations that move a card-present session, for every terminal in the process, because
/// the device has one card reader and one read at a time.
@MainActor
final class SessionSetupGate {
    static let shared = SessionSetupGate()

    /// An operation holding the gate.
    private struct Holder {
        let kind: SessionSetupKind
        /// The terminal it belongs to.
        let owner: ObjectIdentifier
        let task: Task<Void, Error>
        /// Tells it from the next operation, so only it clears the slot.
        let id: Int
    }

    private var inFlight: Holder?
    private var nextID = 0

    /// Bumped every time any terminal prepares a reader. A charge captures it before the tap, so a failure
    /// that arrives after the reader was prepared again is not attributed to the new one.
    var readerGeneration = 0

    /// True while a charge holds the gate, running or still waiting for the operation before it.
    var isHeldByCharge: Bool {
        inFlight?.kind == .charge
    }

    /// Runs `work` once the operation holding the gate has finished. A caller of the same kind on the same
    /// terminal joins the one in flight instead.
    ///
    /// - Parameters:
    ///   - kind: The operation.
    ///   - owner: The terminal it belongs to.
    ///   - work: The operation's body, run in a task no caller owns, so a cancelled caller does not stop it.
    func run(
        _ kind: SessionSetupKind,
        for owner: ObjectIdentifier,
        _ work: @escaping @MainActor () async throws -> Void
    ) async throws {
        if let existing = inFlight, existing.kind == kind, existing.owner == owner {
            return try await existing.task.value
        }

        // Chains behind the operation holding the gate. Re-checking in a loop
        // re-awaits a task that has already finished and spins the main actor
        // until the slot is cleared, starving everything else on it.
        let previous = inFlight?.task
        let id = claimID()

        let task = Task<Void, Error> { @MainActor in
            // Its failure belongs to its own caller.
            if let previous {
                _ = try? await previous.value
            }
            try await work()
        }
        inFlight = Holder(kind: kind, owner: owner, task: task, id: id)
        defer { release(id) }
        try await task.value
    }

    /// Holds the gate for a charge until `body` returns. `body` runs in the caller's task, so cancelling the
    /// charge reaches it.
    ///
    /// - Parameters:
    ///   - owner: The terminal charging.
    ///   - body: The charge.
    /// - Returns: What `body` returns.
    func holdForCharge<T>(for owner: ObjectIdentifier, _ body: @MainActor () async throws -> T) async throws -> T {
        // Claimed before the first suspension, so a setup call made while the
        // charge waits for the previous one chains behind the charge.
        let previous = inFlight?.task
        let id = claimID()
        let (released, release) = AsyncStream<Void>.makeStream()
        let hold = Task<Void, Error> { @MainActor in
            for await _ in released {}
        }
        inFlight = Holder(kind: .charge, owner: owner, task: hold, id: id)
        defer {
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

    /// Clears the slot only while `id` still holds it, so an operation that chained behind keeps its claim.
    private func release(_ id: Int) {
        if inFlight?.id == id {
            inFlight = nil
        }
    }
}
