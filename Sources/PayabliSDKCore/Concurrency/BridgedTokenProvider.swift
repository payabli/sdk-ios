import Foundation

/// Wraps an ObjC completion-block token source in a `PayabliTokenRefresh` continuation.
///
/// `package` so `PayabliSDKPayInPaymentFlow` and `PayabliSDKTapToPay` share one implementation of
/// cancellation-sensitive logic instead of each carrying its own copy: a fix to one bridge landing
/// without the other is exactly the drift a single caller cannot cause. `errorDomain` is the only
/// thing that varies between them, for the `NSError` a nil token and nil error both produce.
///
/// `pending` holds the continuation between setup and whichever of the host's completion block or a
/// cancellation resumes it first. Swapped to nil by whichever gets there, so the other — a second
/// completion call, or the completion arriving after this task was already cancelled — is a no-op
/// rather than a double resume.
///
/// The cancellation handler exists for a call `PayabliAuth` gave up on, not for the host's ordinary
/// cancellation: `PayabliAuth`'s `racedMint` returns at its deadline whether or not this call has
/// answered, so a caller is never left waiting on it either way. What resuming here prevents is this
/// call otherwise running forever unseen, holding the host's completion and a continuation neither
/// side is waiting on.
///
/// A free function rather than inlined into either `@objc` init, so a test can build one directly
/// and cancel the `Task` running it with `Task.cancel()`, instead of driving `PayabliAuth`'s real
/// 30s bound (or, for the TapToPay side, its `initialize()` pipeline — which App Attest refuses on a
/// simulator before that pipeline ever reaches this call) to reach the same cancellation path.
package func bridgedTokenProvider(
    errorDomain: String,
    _ tokenHandler: @escaping (@escaping (String?, NSError?) -> Void) -> Void
) -> PayabliTokenRefresh {
    let sendable = UncheckedSendableBox(tokenHandler)
    return {
        let pending = Locked<CheckedContinuation<String, Error>?>(nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                pending.withLock { $0 = continuation }
                // A cancellation that raced this setup found nothing to resume yet; caught here
                // instead, so a task already cancelled when this call started does not wait on a
                // host that will never call back.
                guard !Task.isCancelled else {
                    let toResume = pending.withLock { stored -> CheckedContinuation<String, Error>? in
                        defer { stored = nil }
                        return stored
                    }
                    toResume?.resume(throwing: CancellationError())
                    return
                }
                sendable.value { token, error in
                    let toResume = pending.withLock { stored -> CheckedContinuation<String, Error>? in
                        defer { stored = nil }
                        return stored
                    }
                    guard let toResume else { return }
                    if let error {
                        toResume.resume(throwing: error)
                    } else if let token {
                        toResume.resume(returning: token)
                    } else {
                        toResume.resume(throwing: NSError(
                            domain: errorDomain,
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey:
                                "tokenHandler returned nil token and nil error"]
                        ))
                    }
                }
            }
        } onCancel: {
            let toResume = pending.withLock { stored -> CheckedContinuation<String, Error>? in
                defer { stored = nil }
                return stored
            }
            toResume?.resume(throwing: CancellationError())
        }
    }
}

/// Threads an ObjC block through a Swift `@Sendable` closure. ObjC blocks are heap-allocated and
/// copy-on-capture, but Swift does not infer `@Sendable` for the input function type; this opts out
/// of that check explicitly at the boundary.
///
/// Not `package`: only `bridgedTokenProvider` above needs to be reachable from the other targets,
/// and this stays an implementation detail of it.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) {
        self.value = value
    }
}

/// `NSLock`-backed reference cell used as a one-shot guard when bridging ObjC completion blocks
/// into a `CheckedContinuation`. The host might invoke a completion block more than once —
/// `CheckedContinuation` crashes on the second resume — so this cell serializes whether the resume
/// has already happened. Reference type so the closure mutates shared state without `var` capture
/// warnings under strict concurrency. Not `package`, for the same reason as `UncheckedSendableBox`
/// above.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    /// Mutates and returns whatever the caller derives from the protected
    /// state, atomically. Use the inout argument to read+write.
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
