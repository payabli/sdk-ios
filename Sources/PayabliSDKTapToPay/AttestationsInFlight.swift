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
    /// The entry points a turn is running for.
    private var running: Set<String> = []

    /// Who is waiting for each entry point, in arrival order.
    ///
    /// Suspended callers, so a cancellation can resume one directly. `Task.value`
    /// does not resume when the awaiting task is cancelled, so a chain of tasks
    /// awaiting each other holds a cancelled caller until the attestation ahead of
    /// it finishes.
    private var waiting: [String: [Waiter]] = [:]

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    func takingTurns<T>(
        _ entry: String,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await waitForTurn(entry)
        do {
            // A caller cancelled while queued must not register a device once its
            // turn arrives.
            try Task.checkCancellation()
            let value = try await work()
            handOn(entry)
            return value
        } catch {
            handOn(entry)
            throw error
        }
    }

    /// Returns once this caller holds the entry point, or raises if it is cancelled
    /// first.
    private func waitForTurn(_ entry: String) async throws {
        guard running.contains(entry) else {
            running.insert(entry)
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Checked here, where nothing suspends between the check and the
                // append: a caller already cancelled on arrival would otherwise be
                // abandoned before it was queued, and then never resumed at all.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiting[entry, default: []].append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.abandon(entry, id) }
        }
    }

    /// Releases a caller that was cancelled while queued. The turn ahead is left
    /// alone: it belongs to a caller that did not cancel.
    private func abandon(_ entry: String, _ id: UUID) {
        guard var queue = waiting[entry],
              let index = queue.firstIndex(where: { $0.id == id })
        else {
            return
        }
        let waiter = queue.remove(at: index)
        waiting[entry] = queue.isEmpty ? nil : queue
        waiter.continuation.resume(throwing: CancellationError())
    }

    /// Passes the entry point to the next caller, or gives it up when none is
    /// waiting.
    private func handOn(_ entry: String) {
        guard var queue = waiting[entry], !queue.isEmpty else {
            running.remove(entry)
            return
        }
        let next = queue.removeFirst()
        waiting[entry] = queue.isEmpty ? nil : queue
        // `running` stays set: the turn is passed on rather than released.
        next.continuation.resume()
    }
}
