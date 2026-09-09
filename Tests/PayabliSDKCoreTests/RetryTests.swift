@testable import PayabliSDKCore
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

    /// A hint that is not a wait reads as no hint rather than as a wait of none.
    ///
    /// `PayabliRetryAfter` is public, so a conformer outside the SDK supplies this value and nothing the
    /// policy validated covers it. A NaN passes the ceiling test and the budget test alike, because every
    /// comparison against one is false, and then reaches the clock as no wait at all: the attempts run
    /// back to back. A negative one is not an instruction either.
    func testAHintThatIsNotAWaitFallsBackToTheComputedBackoff() async {
        for hint: TimeInterval in [.nan, -1, -.infinity] {
            let clock = FakeRetryClock()

            _ = try? await Retry.run(
                policy: .test(maxAttempts: 2),
                logger: logger(RecordingLogSink()),
                clock: clock
            ) { _ in
                throw TestHintedFailure(code: .rateLimited, retryAfter: hint)
            }

            XCTAssertEqual(clock.waits, [1], "a hint of \(hint) leaves the computed backoff in place")
        }
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

    /// A 408 says the request never arrived, so repeating it is safe and the policy has to agree. It was
    /// retryable under the status-based classification this replaced, and would otherwise have been lost.
    func testARequestTimeoutIsRetryable() throws {
        let response = PayabliResponse(statusCode: 408, headers: [:], body: Data())
        do {
            try mapPayabliHTTPError(response: response)
            XCTFail("expected a 408 to map to an error")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.code, .networkError)
            XCTAssertTrue(RetryPolicy.retryableByCode(error))
        }
    }

    func testATokenExpiryIsNotRetryableSoTheTwoLayersDoNotOverlap() {
        // Recovering from a refused credential belongs to the transport below. Retrying it here would
        // spend the policy on refresh-and-replay cycles around a credential that is settled.
        XCTAssertFalse(RetryPolicy.retryableCodes.contains(.tokenExpired))
        XCTAssertFalse(RetryPolicy.retryableByCode(TestFailure(.tokenExpired)))
    }

    /// The runner asks the policy rather than classifying for itself.
    ///
    /// Every other case here uses the default predicate, so a runner that hard-coded it would pass all of
    /// them. These two supply a predicate that disagrees with the default in both directions.
    func testTheRunnerAsksThePolicyRatherThanClassifyingForItself() async {
        let retriedAnyway = AttemptCounter()
        _ = try? await Retry.run(
            policy: RetryPolicy(
                maxAttempts: 2,
                baseDelay: 0,
                maxDelay: 0,
                multiplier: 1,
                maxJitter: 0,
                jitter: .none,
                isRetryable: { $0.code == .paymentDeclined }
            ),
            logger: logger(RecordingLogSink()),
            clock: FakeRetryClock()
        ) { _ in
            _ = await retriedAnyway.next()
            throw TestFailure(.paymentDeclined)
        }
        await assertEqualAwaiting(
            await retriedAnyway.count, 2,
            "a decline is retried when the policy says so"
        )

        let stoppedAnyway = AttemptCounter()
        _ = try? await Retry.run(
            policy: RetryPolicy(
                maxAttempts: 3,
                baseDelay: 0,
                maxDelay: 0,
                multiplier: 1,
                maxJitter: 0,
                jitter: .none,
                isRetryable: { _ in false }
            ),
            logger: logger(RecordingLogSink()),
            clock: FakeRetryClock()
        ) { _ in
            _ = await stoppedAnyway.next()
            throw TestFailure(.serverError)
        }
        await assertEqualAwaiting(
            await stoppedAnyway.count, 1,
            "a server fault stops when the policy says so"
        )
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

    /// A wait that fits when planned can still overrun: the clock keeps counting while the device is
    /// suspended. The failure that caused the wait is what reaches the caller, not a synthetic timeout.
    func testABackoffThatOverrunsTheBudgetStillReportsTheFailureThatCausedIt() async {
        let clock = FakeRetryClock()

        do {
            _ = try await Retry.run(
                policy: .test(maxAttempts: 5, totalTimeout: 1.2),
                logger: logger(RecordingLogSink()),
                clock: clock
            ) { attempt in
                if attempt == 1 {
                    // Lands the clock past the deadline during the wait that follows, which the planned
                    // 1s wait would not have done on its own.
                    clock.advance(by: 0.4)
                }
                throw TestFailure(.serverError, reason: "the one that caused the wait")
            }
            XCTFail("expected the retry to stop")
        } catch let error as TestFailure {
            XCTAssertEqual(error.reason, "the one that caused the wait")
        } catch let error as PayabliGenericError {
            XCTFail("the real failure was discarded for: \(error.reason)")
        } catch {
            XCTFail("unexpected \(error)")
        }
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
        let entered = Latch()

        // Opened only once the attempt is under way. Opening it first lets the deadline finish before the
        // operation has run at all, and the attempt count then holds for the wrong reason.
        let run = Task {
            try await Retry.run(
                policy: .test(maxAttempts: 5, totalTimeout: 0.5),
                logger: logger(RecordingLogSink()),
                clock: clock
            ) { _ in
                _ = await counter.next()
                entered.open()
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return "never"
            }
        }
        await entered.wait()
        clock.openTheDeadline()

        do {
            _ = try await run.value
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

    /// A cancellation landing during the wait stops the next attempt.
    ///
    /// The loop checks cancellation where it catches a failure, so one arriving before that is already
    /// seen. This is the window after it: a wait of zero seconds observes nothing, and `Retry-After: 0`
    /// is a value a server may send, so without a check at the top of the loop the attempt goes out.
    func testACancellationDuringTheWaitStopsTheNextAttempt() async {
        let clock = SleepHookClock()
        let counter = AttemptCounter()
        let holder = TaskHolder()

        // The run waits on this, so the hook and the holder are in place before the first wait. Without
        // it the task can reach that wait while the hook is still nil, and the case asserts nothing.
        let ready = Latch()
        let task = Task {
            await ready.wait()
            return try await Retry.run(
                policy: .test(maxAttempts: 5, baseDelay: 0, maxDelay: 0),
                logger: logger(RecordingLogSink()),
                clock: clock
            ) { _ in
                _ = await counter.next()
                throw TestHintedFailure(code: .rateLimited, retryAfter: 0)
            }
        }
        holder.hold(task)
        clock.onSleep { holder.cancel() }
        ready.open()

        _ = try? await task.value

        let attempts = await counter.count
        XCTAssertEqual(attempts, 1, "a cancellation during the wait leaves the next attempt unsent")
    }

    /// A caller cancelled while the refresh is failing is cancelled, not told what the provider said.
    ///
    /// The check after the join only guards the success path unless the result is awaited: a refresh that
    /// throws would otherwise throw straight past it, and a direct transport caller outside `Retry.run`
    /// would read a provider failure where its own cancellation is the answer.
    func testCancellingWhileJoiningAFailingRefreshReportsCancellation() async throws {
        struct ProviderFailure: Error {}

        let released = Latch()
        let providerCalls = Counter()
        let stub = RecordingStub { _ in (401, Data()) }
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: {
            _ = await providerCalls.increment()
            await released.wait()
            throw ProviderFailure()
        })
        let transport = makeAuthenticatedStack(auth: auth)

        let task = Task {
            try await transport.perform(PayabliRequest(method: .get, path: "/api/v2/ping"))
        }

        // Cancelling before the refresh is under way would take the ordinary path and prove nothing.
        var started = false
        for _ in 0 ..< 300 where !started {
            if await providerCalls.count == 1 {
                started = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(started, "the refresh never started, so nothing was joined")

        task.cancel()
        released.open()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // The only acceptable outcome.
        } catch is ProviderFailure {
            XCTFail("the provider's failure was reported to a caller that had been cancelled")
        } catch {
            XCTFail("cancellation surfaced as \(type(of: error)): \(error)")
        }
    }

    /// Cancelling while waiting on a shared refresh stops the recovery instead of replaying.
    ///
    /// The other cancellation cases cancel an HTTP request in flight and never reach this: the join goes
    /// through `Task.value`, which does not observe the awaiting task's cancellation, so the refresh
    /// would complete, hand back its token, and the recovery would send the request again.
    func testCancellingWhileJoiningARefreshDoesNotReplay() async throws {
        let released = Latch()
        let providerCalls = Counter()
        let stub = RecordingStub { _ in (401, Data()) }
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: {
            _ = await providerCalls.increment()
            // Held open so the cancellation lands while the refresh is still running.
            await released.wait()
            return "refreshed-token"
        })
        let transport = makeAuthenticatedStack(auth: auth)

        let task = Task {
            try await transport.perform(PayabliRequest(method: .get, path: "/api/v2/ping"))
        }

        // The first send has to have been refused and the refresh started before cancelling, or this
        // would be testing a cancellation that arrived before the join. Bounded, so a refresh that never
        // starts fails here rather than hanging the suite.
        var started = false
        for _ in 0 ..< 200 where !started {
            if await providerCalls.count == 1 {
                started = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(started, "the refresh never started, so nothing was joined")
        task.cancel()
        released.open()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // The only acceptable outcome.
        } catch {
            XCTFail("cancellation surfaced as \(type(of: error)): \(error)")
        }

        XCTAssertEqual(stub.count, 1, "the request is not sent again after a cancelled join")
    }

    /// The path the case below cannot reach. `PayabliService.perform` wraps what `URLSession` throws, and
    /// a cancelled request arriving as a transient failure would be retried: the caller who cancelled
    /// gets the request sent again and is told the network failed.
    ///
    /// Driven through a real service over a stub that never answers, so the cancellation is the one
    /// `URLSession` raises rather than one this case constructed.
    func testCancellingAServiceBackedAttemptIsNotRetried() async throws {
        let stub = RecordingStub { _ in (200, Data()) }
        stub.installNeverAnswering()
        defer { stub.uninstall() }

        let auth = try makeTestAuth()
        let transport = makeAuthenticatedStack(auth: auth)

        // A clock that neither suspends nor observes cancellation, so a retry that should not happen is
        // free to happen. Waiting on `Task.sleep` here would raise on the cancelled task and report
        // cancellation whatever the code under test did.
        let task = Task {
            try await Retry.run(
                policy: .test(maxAttempts: 3),
                logger: logger(RecordingLogSink()),
                clock: ImmediateRetryClock()
            ) { _ in
                try await transport.perform(PayabliRequest(method: .get, path: "/api/v2/ping"))
            }
        }
        // Cancelling before the request reaches the transport would satisfy every assertion below without
        // the URLSession cancellation ever being translated, which is what this case is about.
        await stub.waitUntilRequestArrives()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // The only acceptable outcome.
        } catch let error as PayabliGenericError {
            XCTFail("cancellation was reported as \(error.code.rawValue): \(error.reason)")
        }

        XCTAssertLessThanOrEqual(stub.count, 1, "a cancelled request is not sent again")
    }

    func testCancellingTheCallerStaysCancellationRatherThanBecomingABudgetFailure() async {
        let clock = FakeRetryClock()

        let entered = Latch()
        let task = Task {
            try await Retry.run(
                policy: .test(maxAttempts: 5, totalTimeout: 30),
                logger: logger(RecordingLogSink()),
                clock: clock
            ) { _ in
                entered.open()
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return "never"
            }
        }
        // Cancelling first is answered by the check at the top of the loop, which is a different guard
        // from the one this case is about: cancellation inside a budgeted attempt staying cancellation.
        await entered.wait()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // The only acceptable outcome. The operation here is `Task.sleep`, which raises exactly this
            // on cancellation, so accepting anything else would let an unrelated failure satisfy a case
            // named for cancellation propagating.
        } catch {
            XCTFail("cancellation surfaced as \(type(of: error)): \(error)")
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
