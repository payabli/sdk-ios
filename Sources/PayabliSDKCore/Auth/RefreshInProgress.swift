import Foundation

/// The holders whose own provider call this task is inside, outermost first, so a request a provider
/// issues can be told apart from one merely waiting on a refresh.
///
/// A chain rather than one holder, because a provider may call a second session whose provider calls
/// back into the first. Recording only the innermost leaves the outer holder unmarked, and its own
/// refresh is the one that call would then join and wait on forever.
///
/// Identity rather than equality, and a chain rather than a flag: a request through a holder that is
/// not in it must still join that holder's refresh normally.
///
/// Bound around a provider call and nothing else. A provider that hops to an unrelated task leaves
/// the binding behind and is treated as any other caller.
enum RefreshInProgress {
    @TaskLocal static var holders: [PayabliAuth] = []

    /// Whether this task is already inside `auth`'s own provider call, at any depth.
    static func contains(_ auth: PayabliAuth) -> Bool {
        holders.contains { $0 === auth }
    }

    /// Runs `operation` with `auth` appended, so every enclosing holder stays marked.
    static func withHolder<T>(
        _ auth: PayabliAuth,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $holders.withValue(holders + [auth], operation: operation)
    }
}
