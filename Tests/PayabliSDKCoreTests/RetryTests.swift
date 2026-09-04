@_spi(PayabliInternal) @testable import PayabliSDKCore
import XCTest

/// Ported from the sibling SDK's retry suite. Every timing assertion runs on `FakeRetryClock`, so an
/// elapsed total is exact and costs nothing.
final class RetryTests: XCTestCase {
    private func logger(_ sink: RecordingLogSink) -> PayabliLogger {
        PayabliLogger(category: .network, sink: sink)
    }

    // MARK: - Attempts

    func testAFlakyOperationThatFailsThenSucceedsIsRetried() async throws {
        let clock = FakeRetryClock()
        let counter = AttemptCounter()

        let value = try await Retry.run(policy: .test(), logger: logger(RecordingLogSink()), clock: clock) { _ in
            let attempt = await counter.next()
            if attempt == 1 {
                throw TestFailure(.serverError)
            }
            return "ok"
        }

        XCTAssertEqual(value, "ok")
        await assertEqualAwaiting(await counter.count, 2)
    }

    func testAnAlwaysFailingOperationThrowsTheUnderlyingErrorRatherThanAWrapper() async {
        let clock = FakeRetryClock()
        let counter = AttemptCounter()

        do {
            _ = try await Retry.run(policy: .test(), logger: logger(RecordingLogSink()), clock: clock) { _ in
                _ = await counter.next()
                throw TestFailure(.serverError, reason: "the real cause")
            }
            XCTFail("expected the operation to fail")
        } catch let error as TestFailure {
            XCTAssertEqual(error.reason, "the real cause")
        } catch {
            XCTFail("expected the underlying failure, got \(error)")
        }

        await assertEqualAwaiting(await counter.count, 3)
    }

    // MARK: - Backoff

    func testBackoffIsExponentialAndCapped() async {
        let clock = FakeRetryClock()

        _ = try? await Retry.run(
            policy: .test(maxAttempts: 6),
            logger: logger(RecordingLogSink()),
            clock: clock
        ) { _ in
            throw TestFailure(.serverError)
        }

        // Capped at 8, so the fifth wait repeats rather than reaching 16.
        XCTAssertEqual(clock.waits, [1, 2, 4, 8, 8])
    }

    func testTheTotalWaitFollowsTheComputedBackoff() async {
        let clock = FakeRetryClock()

        _ = try? await Retry.run(policy: .test(), logger: logger(RecordingLogSink()), clock: clock) { _ in
            throw TestFailure(.serverError)
        }

        XCTAssertEqual(clock.elapsed(), 3, "1s then 2s across three attempts")
    }

    // MARK: - Retry-After

    func testAServerRetryAfterBeatsTheComputedBackoff() async {
        let clock = FakeRetryClock()

        _ = try? await Retry.run(policy: .test(maxAttempts: 2), logger: logger(RecordingLogSink()), clock: clock) { _ in
            throw TestHintedFailure(code: .rateLimited, retryAfter: 5)
        }

        XCTAssertEqual(clock.waits, [5], "the server's 5s wins over the policy's 1s")
    }

    func testARetryAfterBeyondTheCeilingStopsRatherThanUnderSleeping() async {
        let clock = FakeRetryClock()
        let counter = AttemptCounter()
        let sink = RecordingLogSink()

        do {
            _ = try await Retry.run(policy: .test(), logger: logger(sink), clock: clock) { _ in
                _ = await counter.next()
                throw TestHintedFailure(code: .rateLimited, retryAfter: 3600)
            }
            XCTFail("expected the retry to stop")
        } catch let error as TestHintedFailure {
            XCTAssertEqual(error.code, .rateLimited, "the server's own refusal, not a synthesised one")
        } catch {
            XCTFail("expected the underlying refusal, got \(error)")
        }

        await assertEqualAwaiting(await counter.count, 1)
        XCTAssertEqual(clock.elapsed(), 0, "shortening the wait would ignore what the server asked for")
        XCTAssertTrue(sink.records.contains { $0.message.contains("retry-after exceeds the ceiling") })
    }

    // MARK: - Classification

    func testADeclineIsNeverRetried() async {
        let counter = AttemptCounter()

        _ = try? await Retry.run(policy: .test(), logger: logger(RecordingLogSink()), clock: FakeRetryClock()) { _ in
            _ = await counter.next()
            throw TestFailure(.paymentDeclined)
        }

        await assertEqualAwaiting(await counter.count, 1)
    }

    /// Iterates the whole vocabulary, so a code added later is proved un-retryable rather than assumed to
    /// be, and a widening of the set has to be a deliberate edit to the case below.
    func testEveryNonRetryableCodeStopsOnTheFirstAttempt() async {
        let nonRetryable = PayabliErrorCode.allCases.filter { !RetryPolicy.retryableCodes.contains($0) }
        XCTAssertFalse(nonRetryable.isEmpty)

        for code in nonRetryable {
            let counter = AttemptCounter()
            _ = try? await Retry.run(
                policy: .test(),
                logger: logger(RecordingLogSink()),
                clock: FakeRetryClock()
            ) { _ in
                _ = await counter.next()
                throw TestFailure(code)
            }
            await assertEqualAwaiting(await counter.count, 1, "\(code.rawValue) must not be retried")
        }
    }

    func testTheRetryableSetIsExactlyTheThreeTransientCodes() {
        XCTAssertEqual(RetryPolicy.retryableCodes, [.networkError, .serverError, .rateLimited])
    }

    func testATokenExpiryIsNotRetryableSoTheTwoLayersDoNotOverlap() {
        // Recovering from a refused credential belongs to the transport below. Retrying it here would
        // spend the policy on refresh-and-replay cycles around a credential that is settled.
        XCTAssertFalse(RetryPolicy.retryableCodes.contains(.tokenExpired))
        XCTAssertFalse(RetryPolicy.retryableByCode(TestFailure(.tokenExpired)))
    }

    func testANonPayabliFailurePropagatesUntouchedAndUnretried() async {
        struct Foreign: Error {}
        let counter = AttemptCounter()

        do {
            _ = try await Retry.run(policy: .test(), logger: logger(RecordingLogSink()), clock: FakeRetryClock()) { _ in
                _ = await counter.next()
                throw Foreign()
            }
            XCTFail("expected the foreign error to escape")
        } catch is Foreign {
            // expected
        } catch {
            XCTFail("expected Foreign, got \(error)")
        }

        await assertEqualAwaiting(await counter.count, 1)
    }

    // MARK: - The total budget

    func testTheTotalBudgetDeclinesAFurtherAttemptAndThrowsTheLastError() async {
        let clock = FakeRetryClock()
        let counter = AttemptCounter()

        do {
            _ = try await Retry.run(
                policy: .test(maxAttempts: 5, totalTimeout: 1.5),
                logger: logger(RecordingLogSink()),
                clock: clock
            ) { _ in
                _ = await counter.next()
                throw TestFailure(.serverError, reason: "the last one")
            }
            XCTFail("expected the budget to stop the retry")
        } catch let error as TestFailure {
            XCTAssertEqual(error.reason, "the last one", "the real failure, not a budget error")
        } catch {
            XCTFail("expected the underlying failure, got \(error)")
        }

        // The 1s wait fits inside 1.5s; the 2s that would follow does not.
        await assertEqualAwaiting(await counter.count, 2)
    }

    func testABackoffWaitConsumesTheBudgetTheNextAttemptGets() async {
        let clock = FakeRetryClock()

        _ = try? await Retry.run(
            policy: .test(maxAttempts: 5, totalTimeout: 1.2),
            logger: logger(RecordingLogSink()),
            clock: clock
        ) { _ in
            throw TestFailure(.serverError)
        }

        // One 1s wait, and the 2s that would follow exceeds the 0.2s left. A budget reset per attempt
        // would have let the whole schedule run.
        XCTAssertEqual(clock.waits, [1])
        XCTAssertEqual(clock.elapsed(), 1)
    }

    func testAnUnboundedPolicyImposesNoDeadlineOfItsOwn() async throws {
        let clock = FakeRetryClock()

        // `nil` is not "some large deadline": nothing may bound the attempt at all.
        let value = try await Retry.run(
            policy: .test(totalTimeout: nil),
            logger: logger(RecordingLogSink()),
            clock: clock
        ) { _ in
            clock.advance(by: 10000)
            return "ok"
        }

        XCTAssertEqual(value, "ok")
    }

    func testTheTotalBudgetCutsOffAnInFlightAttemptAndDoesNotRetry() async {
        let clock = FakeRetryClock()
        let counter = AttemptCounter()

        do {
            _ = try await Retry.run(
                policy: .test(maxAttempts: 5, totalTimeout: 0.5),
                logger: logger(RecordingLogSink()),
                clock: clock
            ) { _ in
                _ = await counter.next()
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return "never"
            }
            XCTFail("expected the budget to cut the attempt off")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.code, .networkError)
            // The reason is asserted too: `.networkError` is also what a refused connection produces, so
            // the code alone would pass against an unrelated network failure.
            XCTAssertEqual(error.reason, "Operation exceeded its total timeout")
        } catch {
            XCTFail("expected a budget failure, got \(error)")
        }

        await assertEqualAwaiting(await counter.count, 1)
    }

    // MARK: - Cancellation

    func testCancellingTheCallerStaysCancellationRatherThanBecomingABudgetFailure() async {
        let clock = FakeRetryClock()

        let task = Task {
            try await Retry.run(
                policy: .test(maxAttempts: 5, totalTimeout: 30),
                logger: logger(RecordingLogSink()),
                clock: clock
            ) { _ in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return "never"
            }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch let error as PayabliGenericError {
            XCTFail("cancellation was reported as \(error.reason)")
        } catch {
            // A cancelled `Task.sleep` may surface as a URLError-shaped cancellation on some paths;
            // what must not happen is a budget error.
            XCTAssertFalse("\(error)".contains("total timeout"))
        }
    }
}

// MARK: - Helpers

func assertEqualAwaiting<T: Equatable>(
    _ actual: @autoclosure () async -> T,
    _ expected: T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let value = await actual()
    XCTAssertEqual(value, expected, message, file: file, line: line)
}
