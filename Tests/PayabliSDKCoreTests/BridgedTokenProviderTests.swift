@testable import PayabliSDKCore
import XCTest

/// The cancellation path `bridgedTokenProvider` exists for: a `tokenHandler` that retains its
/// completion instead of calling it — the "forgotten completion" case a callback-shaped API
/// invites — combined with the `Task` running it being cancelled, which is what `PayabliAuth` does
/// at its bound rather than waiting on this call forever.
///
/// One case here covers both `PayabliSDKPayIn` and `PayabliSDKTapToPay`, which share
/// this implementation. Drives that with `Task.cancel()` directly rather than through either
/// facade's real init and `PayabliAuth`'s 30s bound — `PayabliAuthProviderBoundTests` already
/// proves that bound end to end with a clock double, and TapToPay's `initialize()` pipeline cannot
/// reach the token step on a simulator at all, since App Attest refuses first.
final class BridgedTokenProviderTests: XCTestCase {
    func testResumesWithCancellationErrorWhenCancelledAndIgnoresALateCallback() async throws {
        let handlerCalled = expectation(description: "tokenHandler called")
        var lateCompletion: ((String?, NSError?) -> Void)?
        let provider = bridgedTokenProvider(errorDomain: "com.payabli.test") { completion in
            lateCompletion = completion
            handlerCalled.fulfill()
        }

        let task = Task { try await provider() }
        await fulfillment(of: [handlerCalled], timeout: 1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("a cancelled provider task must throw")
        } catch is CancellationError {
            // Expected: the cancellation handler resumed the parked continuation instead of leaving
            // it running unseen.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        // A crash here (a double resume of the same continuation) is the failure mode this guards:
        // XCTest reporting green on this call proves the guard, not just the catch above.
        lateCompletion?("late-token", nil)
    }

    func testATaskAlreadyCancelledBeforeSetupResumesWithCancellationErrorWithoutCallingTheHost() async throws {
        let taskStarted = Latch()
        let release = Latch()
        var hostCalled = false
        let provider = bridgedTokenProvider(errorDomain: "com.payabli.test") { completion in
            hostCalled = true
            completion("a-token", nil)
        }

        let task = Task<String, Error> {
            taskStarted.open()
            await release.wait()
            return try await provider()
        }

        // Gated rather than raced: cancel() is guaranteed to land before `provider()` ever runs,
        // so this proves the pre-flight `Task.isCancelled` guard rather than the `onCancel` handler
        // the first test above already covers.
        await taskStarted.wait()
        task.cancel()
        release.open()

        do {
            _ = try await task.value
            XCTFail("a task already cancelled before setup must throw")
        } catch is CancellationError {
            // Expected: caught by the guard inside the continuation body, before the host's
            // completion block was ever handed the continuation to resume.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        XCTAssertFalse(hostCalled, "a task already cancelled before setup must never reach the host")
    }

    func testNilTokenAndNilErrorProducesAnErrorTaggedWithTheGivenDomain() async throws {
        let provider = bridgedTokenProvider(errorDomain: "com.payabli.test") { completion in
            completion(nil, nil)
        }

        do {
            _ = try await provider()
            XCTFail("nil token and nil error must throw")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "com.payabli.test")
        }
    }

    func testTheHostsErrorPassesThroughUnchanged() async throws {
        let hostError = NSError(domain: "com.payabli.test.host", code: 7)
        let provider = bridgedTokenProvider(errorDomain: "com.payabli.test") { completion in
            completion(nil, hostError)
        }

        do {
            _ = try await provider()
            XCTFail("the host's error must propagate")
        } catch let error as NSError {
            XCTAssertEqual(error, hostError)
        }
    }

    func testTheHostsTokenPassesThroughUnchanged() async throws {
        let provider = bridgedTokenProvider(errorDomain: "com.payabli.test") { completion in
            completion("a-token", nil)
        }

        let token = try await provider()
        XCTAssertEqual(token, "a-token")
    }
}
