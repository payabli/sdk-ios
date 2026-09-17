@testable import PayabliSDKCore
import XCTest

/// Split from `PayabliAuthTests` rather than added to it: that class is already at the
/// `type_body_length` ceiling, and this bound is its own concern — what happens to a mint the
/// provider never finishes — distinct from the mint's ordinary success and rejection paths.
final class PayabliAuthProviderBoundTests: XCTestCase {
    /// A provider that never returns is refused once the deadline passes rather than left waiting on
    /// forever — the whole reason for the bound. `Task.sleep(.max)` is cancellation-cooperative, so the
    /// deadline actually lands instead of orphaning the call.
    func testAProviderThatNeverReturnsIsRefusedAtTheDeadline() async throws {
        let auth = PayabliAuth(
            config: try makeConfig(tokenProvider: {
                try await Task.sleep(nanoseconds: .max)
                return "never"
            }),
            logger: PayabliLogger(category: .auth),
            clock: FiresOnceRetryClock()
        )

        let outcome = await outcomeWithinCeiling {
            do {
                _ = try await auth.currentAccessToken()
                return "no throw"
            } catch let err as PayabliGenericError {
                return err.code.rawValue
            } catch {
                return "wrong error: \(error)"
            }
        }

        XCTAssertEqual(outcome, PayabliErrorCode.tokenProviderFailed.rawValue)
    }

    /// Every caller joined to the one mint that times out receives the same failure, not just the
    /// caller who started it — the mint is shared, and the timeout is a property of that one call.
    ///
    /// Bounded the same way `outcomeWithinCeiling`'s own callers are: an unordered arrival at the
    /// actor could in principle land one caller after `releaseMint` and start a second mint, which
    /// `FiresOnceRetryClock` never times out again, so an unbounded wait here would hang the suite
    /// on that caller rather than fail on it.
    func testConcurrentCallersJoinedToATimedOutMintAllReceiveTheSameFailure() async throws {
        let auth = PayabliAuth(
            config: try makeConfig(tokenProvider: {
                try await Task.sleep(nanoseconds: .max)
                return "never"
            }),
            logger: PayabliLogger(category: .auth),
            clock: FiresOnceRetryClock()
        )

        let outcome = await outcomeWithinCeiling {
            let outcomes = await withTaskGroup(of: String.self) { group in
                for _ in 0 ..< 5 {
                    group.addTask {
                        do {
                            _ = try await auth.currentAccessToken()
                            return "no throw"
                        } catch let err as PayabliGenericError {
                            return err.code.rawValue
                        } catch {
                            return "wrong error: \(error)"
                        }
                    }
                }
                var seen: [String] = []
                for await outcome in group {
                    seen.append(outcome)
                }
                return seen
            }
            return outcomes.joined(separator: ",")
        }

        guard let outcome else {
            return XCTFail("the joined callers never all finished")
        }
        let expected = Array(repeating: PayabliErrorCode.tokenProviderFailed.rawValue, count: 5)
        XCTAssertEqual(outcome, expected.joined(separator: ","))
    }

    /// A mint that times out still releases `inFlightMint`/`inFlightMintID`, the same as any other
    /// failure, so the next call starts a fresh mint rather than finding the holder wedged on the one
    /// that just expired.
    func testAMintThatTimesOutReleasesSoTheNextCallSucceeds() async throws {
        let counter = Counter()
        let auth = PayabliAuth(
            config: try makeConfig(tokenProvider: {
                let call = await counter.increment()
                guard call == 1 else { return "recovered" }
                try await Task.sleep(nanoseconds: .max)
                return "never"
            }),
            logger: PayabliLogger(category: .auth),
            clock: FiresOnceRetryClock()
        )

        let firstOutcome = await outcomeWithinCeiling {
            do {
                _ = try await auth.currentAccessToken()
                return "no throw"
            } catch let err as PayabliGenericError {
                return err.code.rawValue
            } catch {
                return "wrong error: \(error)"
            }
        }
        XCTAssertEqual(firstOutcome, PayabliErrorCode.tokenProviderFailed.rawValue)

        let recovered = await outcomeWithinCeiling {
            (try? await auth.currentAccessToken()) ?? "threw"
        }
        XCTAssertEqual(recovered, "recovered", "a timed-out mint must release its mark for the next call")
        let calls = await counter.count
        XCTAssertEqual(calls, 2)
    }
}
