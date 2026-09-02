import Foundation

/// One refresh, by identity. A mark naming a refresh that has already finished answers nothing.
final class RefreshTicket: Sendable {}

/// The refreshes whose provider call this task is inside, outermost first, so a request a provider
/// issues can be told apart from one merely waiting on a refresh.
///
/// A chain rather than one entry, because a provider may call a second session whose provider calls
/// back into the first. Recording only the innermost leaves the outer session unmarked, and its own
/// refresh is the one that call would then join and wait on forever.
///
/// Each entry names the session and the refresh. The session alone is not enough: an unstructured task
/// inherits these values and outlives the call that set them, so a task a provider left running carries
/// its mark indefinitely and would answer rejections belonging to refreshes that finished long before.
/// The holder checks that the refresh named here is still the one it has in flight.
///
/// The session is named by `ObjectIdentifier` and not held. A mark inherited by such a task lives as
/// long as the task does, and holding the session there would keep it, and the credential it holds,
/// alive after the host had released both. An address can be reused once a session is gone, which is
/// what the refresh half rules out: a later session at the same address has a different refresh.
///
/// Bound around a provider call and nothing else. A provider that hops to a detached task leaves the
/// binding behind and is treated as any other caller.
enum RefreshInProgress {
    struct Mark: Sendable {
        let session: ObjectIdentifier
        let ticket: RefreshTicket
    }

    @TaskLocal static var marks: [Mark] = []

    /// Whether this task is inside `auth`'s own provider call for `ticket`, at any depth.
    static func carries(_ auth: PayabliAuth, ticket: RefreshTicket) -> Bool {
        let session = ObjectIdentifier(auth)
        return marks.contains { $0.session == session && $0.ticket === ticket }
    }

    /// Runs `operation` with this refresh appended, so every enclosing one stays marked.
    static func withMark<T>(
        holder: PayabliAuth,
        ticket: RefreshTicket,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $marks.withValue(
            marks + [Mark(session: ObjectIdentifier(holder), ticket: ticket)],
            operation: operation
        )
    }
}
