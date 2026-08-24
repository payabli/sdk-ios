import Foundation

/// The attestation running for each entry point, so a second caller for one entry
/// point takes the answer being produced instead of producing another.
///
/// An actor rather than a lock: what is serialized spans several `await`s, and a
/// lock held across one is a lock held while the thread it was taken on runs
/// something else.
///
/// Joining, not queueing. A caller that waited and then ran its own sequence would
/// register a second device for a paypoint the first call just enrolled, which is
/// the outcome the gate exists to prevent. Taking the first answer also keeps a
/// refusal intact: a device left awaiting activation reports that to both callers,
/// where a second sequence would find a binding, find its key sound, and report a
/// device ready that is not.
actor AttestationsInFlight {
    private var running: [String: Task<AttestationResult, Error>] = [:]

    func joining(
        _ entry: String,
        _ work: @escaping @Sendable () async throws -> AttestationResult
    ) async throws -> AttestationResult {
        if let existing = running[entry] {
            return try await existing.value
        }

        let task = Task { try await work() }
        running[entry] = task
        defer {
            // Only its own. A later attempt for this entry point has replaced the
            // slot by the time a cancelled or failed one gets here.
            if running[entry] == task {
                running[entry] = nil
            }
        }
        return try await task.value
    }
}
