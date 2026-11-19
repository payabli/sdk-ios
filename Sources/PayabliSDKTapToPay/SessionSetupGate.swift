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

    /// Which setup a later call joins: one of an equal `kind`, from the same `PayabliTTP`.
    private struct SetupKey: Hashable {
        let owner: ObjectIdentifier
        let kind: SessionSetupKind
    }

    /// The operation that claimed the gate last, which the next caller chains behind.
    private var last: Claim?
    /// Each `PayabliTTP`'s pending setups, one per kind, until the call that started it returns or a charge claims
    /// the gate.
    private var setups: [SetupKey: Claim] = [:]
    private var nextID = 0

    /// Bumped every time any `PayabliTTP` prepares a reader. A charge captures it before the tap, so a failure
    /// that arrives after the reader was prepared again is not attributed to the new one.
    var readerGeneration = 0

    /// The charge holding the gate, from the moment it claims the gate until it returns, whether it is running,
    /// waiting for the operation before it, or has setups queued behind it.
    private(set) var runningCharge: RunningCharge?

    /// Ends when the running charge returns: what a close on its entry point waits for.
    private var runningChargeEnds: Task<Void, Error>?

    /// The closes holding each entry point, counted from the call until it returns, whether sending or waiting.
    private var closes: [String: Int] = [:]

    /// Runs `work` after every operation already in the gate, or joins `owner`'s pending setup of an equal `kind`.
    ///
    /// - Parameters:
    ///   - kind: Which setup this is; `owner`'s next call of an equal kind joins it until a charge claims the gate.
    ///   - owner: The `PayabliTTP` calling. Only its own calls join this setup; any other caller waits for it.
    ///   - work: The setup, run in a task no caller owns, so a cancelled caller does not stop it.
    func run(
        _ kind: SessionSetupKind,
        for owner: ObjectIdentifier,
        _ work: @escaping @MainActor () async throws -> Void
    ) async throws {
        let key = SetupKey(owner: owner, kind: kind)
        if let existing = setups[key] {
            return try await existing.task.value
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
        setups[key] = claim
        defer {
            release(claim.id)
            if setups[key]?.id == claim.id {
                setups[key] = nil
            }
        }
        try await claim.task.value
    }

    /// Holds the gate for a charge until `body` returns. `body` runs in the caller's task, so cancelling the
    /// charge reaches it.
    ///
    /// - Parameters:
    ///   - charge: The entry point and sale the charge is for, recorded until `body` returns.
    ///   - body: The charge, run in the caller's task once every operation already in the gate has finished.
    /// - Returns: The charge's result.
    func holdForCharge<T>(_ charge: RunningCharge, _ body: @MainActor () async throws -> T) async throws -> T {
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
        runningCharge = charge
        runningChargeEnds = claim.task
        defer {
            runningCharge = nil
            runningChargeEnds = nil
            release.finish()
            self.release(claim.id)
        }

        if let previous {
            _ = try? await previous.value
        }
        return try await body()
    }

    /// Counts a close on `entryPoint` until ``releaseClose(_:)``, so a charge arriving there meanwhile is refused.
    ///
    /// - Parameter entryPoint: the entry point the close is for.
    /// - Returns: what the close waits for before it sends: the end of the charge running on `entryPoint`, or nil when
    ///   none runs there.
    func admitClose(_ entryPoint: String) -> Task<Void, Error>? {
        closes[entryPoint, default: 0] += 1
        return runningCharge?.entryPoint == entryPoint ? runningChargeEnds : nil
    }

    /// Removes one close from `entryPoint`.
    ///
    /// - Parameter entryPoint: the entry point the close was for.
    func releaseClose(_ entryPoint: String) {
        guard let count = closes[entryPoint] else { return }
        closes[entryPoint] = count > 1 ? count - 1 : nil
    }

    /// Whether a close holds `entryPoint`.
    ///
    /// - Parameter entryPoint: the entry point a charge is for.
    /// - Returns: `true` from a close's call until it returns.
    func isClosing(_ entryPoint: String) -> Bool {
        closes[entryPoint] != nil
    }

    /// The charge holding the gate: the entry point it is for and the sale it describes.
    struct RunningCharge {
        let entryPoint: String
        let sale: ChargeDescription
    }

    private func claimID() -> Int {
        nextID += 1
        return nextID
    }

    /// Clears the last claim only while `id` still holds it, so an operation that chained behind keeps its claim.
    ///
    /// - Parameter id: the claim to clear, only while it is still the last.
    private func release(_ id: Int) {
        if last?.id == id {
            last = nil
        }
    }
}
