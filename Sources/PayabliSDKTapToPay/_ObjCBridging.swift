import Foundation

// Helpers used only by the `@objc` convenience init in `PayabliTTP.swift`.
// They are extracted into their own file so the facade does not carry
// ObjC-bridging plumbing inline. Both types are intentionally `internal`
// (no `public`) — host apps must not see them.

/// Box that lets us thread an ObjC block through a Swift `@Sendable`
/// closure. ObjC blocks are heap-allocated and copy-on-capture, but Swift
/// cannot infer `@Sendable` for the input function type, so we opt out of
/// the check explicitly at the boundary.
struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Tiny `NSLock`-backed reference cell used as a one-shot guard when
/// bridging ObjC completion blocks into a `CheckedContinuation`. The host
/// might invoke a completion block more than once — `CheckedContinuation`
/// crashes on the second resume — so this cell serializes "did I already
/// resume?" Reference type so the closure mutates shared state without
/// `var` capture warnings under strict concurrency.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    /// Mutates and returns whatever the caller derives from the protected
    /// state, atomically. Use the inout argument to read+write.
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
