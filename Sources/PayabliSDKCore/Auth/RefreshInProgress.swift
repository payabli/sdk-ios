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
/// Each entry names the session and the refresh, both by identity. The session alone is not enough:
/// an unstructured task inherits these values and outlives the call that set them, so a task a
/// provider left running carries its mark indefinitely and would answer rejections belonging to
/// refreshes that finished long before. The holder checks that the refresh named here is still the
/// one it has in flight.
///
/// Bound around a provider call and nothing else. A provider that hops to a detached task leaves the
/// binding behind and is treated as any other caller.
enum RefreshInProgress {
    struct Mark: Sendable {
        let holder: PayabliAuth
        let ticket: RefreshTicket
    }

    @TaskLocal static var marks: [Mark] = []

    /// Whether this task is inside `auth`'s own provider call for `ticket`, at any depth.
    static func carries(_ auth: PayabliAuth, ticket: RefreshTicket) -> Bool {
        marks.contains { $0.holder === auth && $0.ticket === ticket }
    }

    /// Runs `operation` with this refresh appended, so every enclosing one stays marked.
    static func withMark<T>(
        holder: PayabliAuth,
        ticket: RefreshTicket,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $marks.withValue(
            marks + [Mark(holder: holder, ticket: ticket)],
            operation: operation
        )
    }
}
