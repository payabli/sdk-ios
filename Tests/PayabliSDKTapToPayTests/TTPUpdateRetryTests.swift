import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// The one production call site that retries, driven end to end.
///
/// The retry engine and the error mapper are covered in isolation, and both stay green if the call site
/// stops raising a non-2xx: a failed update would simply look successful. These cases run the charge
/// pipeline against sequenced responses and count what reached the wire, so that shape fails here.
@MainActor
final class TTPUpdateRetryTests: XCTestCase {
    private static let paymentTransId = "TXN-RETRY"

    override func tearDown() {
        // Released before the handler is dropped: a held-open handler is on a URLProtocol thread and
        // outlives this case otherwise.
        Self.updateResponses.release()
        StubURLProtocol.handler = nil
        Self.updateResponses.reset()
        super.tearDown()
    }

    func testAFailedUpdateIsRetriedAndTheSecondAttemptIsAccepted() async throws {
        Self.updateResponses.script([500, 200])
        let ttp = try await makeReadyTTP()

        _ = try await charge(ttp)

        XCTAssertEqual(Self.updateResponses.sends, 2, "the 500 has to be retried")
    }

    func testATransportLevelRateLimitIsRetriedToo() async throws {
        Self.updateResponses.script([429, 200])
        let ttp = try await makeReadyTTP()

        _ = try await charge(ttp)

        XCTAssertEqual(Self.updateResponses.sends, 2)
    }

    /// A server hint on the wire reaches the policy and ends the retry.
    ///
    /// The parser and the engine are covered apart, and both construct a `PayabliResponse` directly, so
    /// dropping the header while converting the real `HTTPURLResponse` would leave them green while the
    /// shipping client ignored what the server asked for.
    func testARateLimitCarryingAHintAboveTheCeilingIsNotRetried() async throws {
        Self.updateResponses.scriptWithHint([429, 200], retryAfter: "3600")
        let ttp = try await makeReadyTTP()

        _ = try? await charge(ttp)

        XCTAssertEqual(
            Self.updateResponses.sends, 1,
            "a hint past the ceiling ends the retry rather than being shortened"
        )
    }

    /// A decline is authoritative, so repeating it only spends the merchant's time. It reaches the caller
    /// as a failed update, and the reason is the mapped one rather than a bare status.
    func testADeclinedUpdateIsNotRetriedAndReportsWhy() async throws {
        Self.updateResponses.script([402, 200])
        let ttp = try await makeReadyTTP()

        do {
            _ = try await charge(ttp)
            XCTFail("a declined update should reach the caller")
        } catch let PayabliTTPError.updateFailed(reason) {
            XCTAssertTrue(reason.contains("declined"), "got \(reason)")
        }

        XCTAssertEqual(Self.updateResponses.sends, 1, "a decline is not worth a second attempt")
    }

    func testAnUpdateAcceptedFirstTimeIsSentOnce() async throws {
        Self.updateResponses.script([200])
        let ttp = try await makeReadyTTP()

        _ = try await charge(ttp)

        XCTAssertEqual(Self.updateResponses.sends, 1)
    }

    /// Cancelling reaches the caller as cancellation, not as a failed update.
    ///
    /// The retry layer stops repeating a cancelled request, and this is the other half: the call site
    /// converts what it catches into this surface's own error, so without a branch for it a caller who
    /// cancelled would be told the update failed.
    func testCancellingDuringTheUpdateReachesTheCallerAsCancellation() async throws {
        Self.updateResponses.holdOpen()
        let ttp = try await makeReadyTTP()

        let task = Task { try await charge(ttp) }
        // Cancelling during initiate or the card read would raise cancellation without the update ever
        // being reached, which is the branch this case is about.
        await Self.updateResponses.waitUntilEntered()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // The only acceptable outcome.
        } catch let PayabliTTPError.updateFailed(reason) {
            XCTFail("cancellation was reported as a failed update: \(reason)")
        }
    }

    /// The event names what failed, not the wrapper. Once wrapped, a rate limit, a server fault, a
    /// decline and a transport failure all reduce to `updateFailed`, and a host forwarding this to
    /// telemetry cannot tell an outage from a refused card.
    func testTheUpdateFailedEventNamesTheUnderlyingFailure() async throws {
        Self.updateResponses.script([402])
        let ttp = try await makeReadyTTP()

        let stream = ttp.events()
        let collector = Task<String?, Never> {
            for await event in stream {
                if case let .updateFailed(_, error) = event {
                    return error
                }
            }
            return nil
        }

        _ = try? await charge(ttp)

        // Bounded, because the regression this case exists to catch is the event not being emitted, and an
        // unbounded read of the stream would hang the suite rather than report it.
        let deadline = Task {
            guard (try? await Task.sleep(nanoseconds: 2_000_000_000)) != nil else { return }
            collector.cancel()
        }
        let summary = await collector.value
        deadline.cancel()

        // The processor's own code as well as the kind: the stub's body carries `A01`, and it survives
        // the decode into the event. Wrapping first reduced all of this to `updateFailed`.
        XCTAssertEqual(
            try XCTUnwrap(summary, "no updateFailed event arrived"),
            "decline(A01)",
            "a decline reaches telemetry as a decline, not as updateFailed"
        )
    }

    // MARK: - Fixture

    /// Statuses to answer `/MoneyIn/update/` with, in order, and how many arrived. The last entry
    /// repeats, so an over-attempt fails as a count rather than as a network error.
    final class ScriptedUpdates: @unchecked Sendable {
        private let lock = NSLock()
        private var statuses: [Int] = [200]
        private var count = 0

        private var holdSeconds: TimeInterval = 0
        private var hasEntered = false
        private var hint: String?

        /// A `Retry-After` to send with every scripted status, so the wire-to-policy path is exercised
        /// rather than the parser and the engine separately.
        func scriptWithHint(_ statuses: [Int], retryAfter: String) {
            lock.lock()
            defer { lock.unlock() }
            self.statuses = statuses
            count = 0
            holdSeconds = 0
            hasEntered = false
            hint = retryAfter
        }

        var retryAfterHint: String? {
            lock.lock()
            defer { lock.unlock() }
            return hint
        }

        func script(_ statuses: [Int]) {
            lock.lock()
            defer { lock.unlock() }
            self.statuses = statuses
            count = 0
            holdSeconds = 0
            hasEntered = false
            hint = nil
        }

        /// Leaves the update in flight, so a test can cancel one that is genuinely under way. Bounded, so
        /// a test that never cancels fails on its own assertion rather than hanging the suite.
        func holdOpen(forAtMost seconds: TimeInterval = 3) {
            lock.lock()
            defer { lock.unlock() }
            statuses = [200]
            count = 0
            holdSeconds = seconds
            hasEntered = false
        }

        /// Blocks while the case is holding the update open, and answers whether it was.
        ///
        /// Polls so teardown can end it: this runs on a URLProtocol thread, and one still sleeping when
        /// the next case starts serves that case's request and consumes a status from its script.
        func waitWhileHeld() -> Bool {
            lock.lock()
            let held = holdSeconds > 0
            lock.unlock()
            guard held else { return false }

            let deadline = Date().addingTimeInterval(holdSeconds)
            while Date() < deadline {
                lock.lock()
                let stillHeld = holdSeconds > 0
                lock.unlock()
                if !stillHeld {
                    break
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            return true
        }

        /// Ends any hold, so teardown releases a handler rather than waiting out its bound.
        func release() {
            lock.lock()
            defer { lock.unlock() }
            holdSeconds = 0
        }

        func reset() {
            script([200])
        }

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            let status = statuses[min(count, statuses.count - 1)]
            count += 1
            return status
        }

        var sends: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        /// Resumes once the update handler has been entered, so a case acts on a state it established
        /// rather than on elapsed time.
        ///
        /// Bounded, and fails rather than returning: an update that never arrives means the case is about
        /// to cancel something else and call it a cancelled update.
        func waitUntilEntered(
            file: StaticString = #filePath,
            line: UInt = #line
        ) async {
            for _ in 0 ..< 300 {
                if entered {
                    return
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTFail("the update handler was never entered", file: file, line: line)
        }

        func markEntered() {
            lock.lock()
            defer { lock.unlock() }
            hasEntered = true
        }

        var entered: Bool {
            lock.lock()
            defer { lock.unlock() }
            return hasEntered
        }
    }

    static let updateResponses = ScriptedUpdates()

    private func makeReadyTTP() async throws -> PayabliTTP {
        StubURLProtocol.handler = Self.stubHandler
        let config = try PayabliConfig(
            accessToken: "seed_token",
            entryPoint: "e",
            environment: .sandbox
        )
        let ttp = PayabliTTP(
            config: config,
            appId: "appid",
            provider: MockTapToPayProvider(),
            attestation: MockDeviceAttestationService(),
            // Three attempts with no wait: the schedule is the retry suite's subject, the count is this
            // suite's.
            retryPolicy: RetryPolicy(
                maxAttempts: 3,
                baseDelay: 0,
                maxDelay: 0,
                multiplier: 1,
                maxJitter: 0,
                jitter: .none
            ),
            session: StubURLProtocol.makeSession()
        )
        try await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .ready, "the fixture itself is broken if this fails")
        return ttp
    }

    private func charge(_ ttp: PayabliTTP) async throws -> TransactionResult {
        try await ttp.charge(
            type: .sale,
            paymentDetails: PayabliTTPPaymentDetails(amount: 1, currency: "USD")
        )
    }

    private static let stubHandler: StubURLProtocol.Handler = { request in
        let path = request.url?.path ?? ""
        var status = 200
        let body: [String: Any]

        if path.contains("/MoneyIn/initiate") {
            body = ["code": "A01", "data": ["paymentTransId": TTPUpdateRetryTests.paymentTransId]]
        } else if path.contains("/MoneyIn/update/") {
            let script = TTPUpdateRetryTests.updateResponses
            script.markEntered()
            if script.waitWhileHeld() {
                // Released by teardown rather than by its own bound, so the case that follows is not
                // served by a handler still sleeping for this one. A released handler answers without
                // consuming a status: the next script belongs to the next case.
                return (
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]
                    )!,
                    Data()
                )
            }
            status = script.next()
            body = ["code": "A01", "data": ["paymentTransId": TTPUpdateRetryTests.paymentTransId]]
        } else {
            body = [
                "responseCode": 1,
                "isSuccess": true,
                "responseData": [
                    "credentials": [
                        "secretKey": "s",
                        "apiKey": "a",
                        "merchantId": "m",
                        "terminalId": "t"
                    ]
                ],
                "paymentToken": "payment_tok"
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: body)
        var headers = ["Content-Type": "application/json"]
        if let hint = TTPUpdateRetryTests.updateResponses.retryAfterHint {
            headers["Retry-After"] = hint
        }
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!,
            data
        )
    }
}
