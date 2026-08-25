import Foundation

/// One attestation at a time per entry point, across every service in the process.
///
/// **A turn, not an answer.** Callers wait for each other and then each runs its
/// own sequence, which begins by reading its own store. A caller whose store holds
/// the binding the previous turn wrote returns it without touching the network; a
/// caller whose store does not runs the full sequence and gets its own device.
///
/// Handing the previous caller's result back instead would be wrong for two
/// services that do not share a store. This is keyed by entry point alone, and a
/// store has no identity to key on, so services over different storage meet here.
/// Given the answer, the second would report a handle its own store never received
/// and can produce no assertion for.
///
/// An actor rather than a lock: what is serialized spans several `await`s, and a
/// lock held across one is a lock held while the thread it was taken on runs
/// something else.
actor AttestationsInFlight {
    /// The turn each entry point's next caller waits behind.
    private var tail: [String: Task<Void, Never>] = [:]

    func takingTurns<T>(
        _ entry: String,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        // Read and replaced with no `await` between them, so two callers cannot
        // both take the same predecessor and run together.
        let ahead = tail[entry]

        let mine = Task<T, Error> {
            // Waits for the turn ahead to end, not to succeed: its failure belongs
            // to its own caller, and a caller that failed leaves the next one a
            // store to read exactly as a caller that succeeded does.
            await ahead?.value

            // A caller cancelled while queued must not register a device once its
            // turn arrives.
            try Task.checkCancellation()
            return try await work()
        }

        // Type-erased, so what a caller returns does not reach the queue.
        let turn = Task<Void, Never> { _ = try? await mine.value }
        tail[entry] = turn

        defer {
            // Only its own. A caller that arrived while this one ran has already
            // replaced it, and is what the next one waits behind.
            if tail[entry] == turn {
                tail[entry] = nil
            }
        }
        // The turn is a task of its own, so it sits outside the caller's
        // cancellation until this reconnects them.
        return try await withTaskCancellationHandler {
            try await mine.value
        } onCancel: {
            mine.cancel()
        }
    }
}
