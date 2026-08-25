import Foundation

/// One attestation at a time per entry point, across every service in the process.
///
/// A turn, not an answer. Callers wait for each other and then each runs its own
/// sequence, which begins by reading its own store, so each reports only a device
/// it can produce assertions for. This is keyed by entry point alone and a store
/// has no identity to key on, so two services over different storage meet here.
///
/// An actor because what is serialized spans several `await`s, and a lock held
/// across one is held while its thread runs something else.
actor AttestationsInFlight {
    /// The turn each entry point's next caller waits behind.
    private var tail: [String: Task<Void, Never>] = [:]

    func takingTurns<T>(
        _ entry: String,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        // Read and replaced with no `await` between them, so two callers cannot
        // take the same predecessor.
        let ahead = tail[entry]

        let mine = Task<T, Error> {
            // Waits for the turn ahead to end, not to succeed: its failure
            // belongs to its own caller.
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
            // Only its own: a caller that arrived while this one ran has already
            // replaced it.
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
