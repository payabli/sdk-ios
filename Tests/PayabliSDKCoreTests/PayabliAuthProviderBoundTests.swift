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
        let clock = FiresOnceRetryClock()
        let auth = PayabliAuth(
            config: try makeConfig(tokenProvider: {
                try await Task.sleep(nanoseconds: .max)
                return "never"
            }),
            logger: PayabliLogger(category: .auth),
            clock: clock
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
        // Proves this raced the 30s bound the doc on `providerTimeout` promises, not some other
        // number a future edit could quietly drift to.
        XCTAssertEqual(clock.requestedDeadlines, [30])
    }

    /// `Task.sleep` above is cancellation-cooperative, so it would pass equally against a
    /// `TaskGroup`-based race — the implementation `racedMint` replaced, which cannot leave its own
    /// scope until every child has finished and would hang this call forever on a provider that
    /// never notices `cancel()`. This case's provider is that shape instead: parked on a raw
    /// continuation with no `onCancel` handling of its own, standing in for the forgotten-completion
    /// case the bound exists to catch.
    func testAProviderThatIgnoresCancellationIsRefusedAtTheDeadlineRatherThanHangingForever() async throws {
        let auth = PayabliAuth(
            config: try makeConfig(tokenProvider: {
                try await withCheckedThrowingContinuation { (_: CheckedContinuation<String, Error>) in
                    // Never resumed, with no cancellation handling to resume it either — the loser
                    // `racedMint`'s own doc says keeps running unawaited.
                }
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
    /// `GatedFiresOnceRetryClock` holds the deadline until all four joiners are counted, which is what
    /// makes this deterministic rather than probable: the one caller that starts the mint logs nothing
    /// on that path, so counting to four rather than five is exactly the other callers, whichever
    /// five of them they are.
    func testConcurrentCallersJoinedToATimedOutMintAllReceiveTheSameFailure() async throws {
        let admitted = Latch()
        let logger = PayabliLogger(
            category: .auth,
            sink: AdmissionCountingLogSink(admittingOn: "Joining an in-flight token mint", occurrence: 4, admitted: admitted)
        )
        let auth = PayabliAuth(
            config: try makeConfig(tokenProvider: {
                try await Task.sleep(nanoseconds: .max)
                return "never"
            }),
            logger: logger,
            clock: GatedFiresOnceRetryClock(admittedAfter: admitted)
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
