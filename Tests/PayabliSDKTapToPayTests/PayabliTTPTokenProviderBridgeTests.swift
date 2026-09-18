@testable import PayabliSDKTapToPay
import XCTest

/// The cancellation path `bridgedTapToPayTokenProvider` exists for: a `tokenHandler` that retains
/// its completion instead of calling it — the "forgotten completion" case a callback-shaped API
/// invites — combined with the `Task` running it being cancelled, which is what `PayabliAuth` does
/// at its bound rather than waiting on this call forever.
///
/// Drives that with `Task.cancel()` directly rather than through `PayabliTTP`'s `initialize()`
/// pipeline and `PayabliAuth`'s real 30s bound: App Attest refuses on a simulator before
/// `initialize()` ever reaches the token step, so that path cannot be exercised in this suite at
/// all, and `PayabliAuthProviderBoundTests` already proves the 30s bound itself with a clock double.
final class PayabliTTPTokenProviderBridgeTests: XCTestCase {
    func testBridgedTokenProviderResumesWithCancellationErrorWhenCancelledAndIgnoresALateCallback() async throws {
        let handlerCalled = expectation(description: "tokenHandler called")
        var lateCompletion: ((String?, NSError?) -> Void)?
        let provider = bridgedTapToPayTokenProvider { completion in
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
}
