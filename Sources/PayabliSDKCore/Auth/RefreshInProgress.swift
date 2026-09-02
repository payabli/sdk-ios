import Foundation

/// Marks the task running a holder's own provider call, so a request that provider issues can be told
/// apart from one merely waiting on the refresh.
///
/// Carries the holder rather than a flag: a provider may issue its request through a different
/// session's transport, and that request must still join the other holder's refresh normally.
///
/// Bound around the provider call and nothing else. A provider that hops to an unrelated task leaves
/// the binding behind and is treated as any other caller.
enum RefreshInProgress {
    @TaskLocal static var current: PayabliAuth?
}
