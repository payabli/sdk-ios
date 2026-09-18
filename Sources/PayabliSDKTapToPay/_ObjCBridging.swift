import Foundation
import PayabliSDKCore

// Helpers used by the `@objc`-bridged token providers in `PayabliTTP.swift` and
// `PayabliPayInPaymentFlow+ObjC.swift`. Kept out of those facades so the ObjC-bridging plumbing
// stays in one place. Both types are `internal`: host apps do not see them.

/// Threads an ObjC block through a Swift `@Sendable` closure. ObjC blocks are heap-allocated and
/// copy-on-capture, but Swift does not infer `@Sendable` for the input function type; this opts out
/// of that check explicitly at the boundary.
struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) {
        self.value = value
    }
}

/// `NSLock`-backed reference cell used as a one-shot guard when bridging ObjC completion blocks
/// into a `CheckedContinuation`. The host might invoke a completion block more than once —
/// `CheckedContinuation` crashes on the second resume — so this cell serializes whether the resume
/// has already happened. Reference type so the closure mutates shared state without `var` capture
/// warnings under strict concurrency.
final class Locked<Value>: @unchecked Sendable {
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

/// Wraps `tokenHandler`'s completion-block shape in a `PayabliTokenRefresh` continuation.
///
/// A free function rather than inlined into the `@objc` init in `PayabliTTP.swift`, so a test can
/// build one directly and cancel the `Task` running it with `Task.cancel()` — exercising this
/// cancellation handling at the point it lives, instead of driving `PayabliAuth`'s real 30s bound
/// (and this facade's `initialize()` pipeline, which App Attest refuses on a simulator before ever
/// reaching this call) to reach the same path.
///
/// `pending` holds the continuation between setup and whichever of the host's completion block or a
/// cancellation resumes it first. Swapped to nil by whichever gets there, so the other — a second
/// completion call, or the completion arriving after this task was already cancelled — is a no-op
/// rather than a double resume.
///
/// The cancellation handler exists for a call `PayabliAuth` gave up on, not for the host's ordinary
/// cancellation: `racedMint` returns at its deadline whether or not this call has answered, so a
/// caller is never left waiting on it either way. What resuming here prevents is this call otherwise
/// running forever unseen, holding `tokenHandler` and a continuation neither side is waiting on.
func bridgedTapToPayTokenProvider(
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
                            domain: "com.payabli.ttp",
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
