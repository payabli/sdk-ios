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
        // Long enough for the update to be in flight, short enough not to be why a run is slow.
        try await Task.sleep(nanoseconds: 300_000_000)
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

    // MARK: - Fixture

    /// Statuses to answer `/MoneyIn/update/` with, in order, and how many arrived. The last entry
    /// repeats, so an over-attempt fails as a count rather than as a network error.
    final class ScriptedUpdates: @unchecked Sendable {
        private let lock = NSLock()
        private var statuses: [Int] = [200]
        private var count = 0

        private var holdSeconds: TimeInterval = 0

        func script(_ statuses: [Int]) {
            lock.lock()
            defer { lock.unlock() }
            self.statuses = statuses
            count = 0
            holdSeconds = 0
        }

        /// Leaves the update in flight, so a test can cancel one that is genuinely under way. Bounded, so
        /// a test that never cancels fails on its own assertion rather than hanging the suite.
        func holdOpen(forAtMost seconds: TimeInterval = 3) {
            lock.lock()
            defer { lock.unlock() }
            statuses = [200]
            count = 0
            holdSeconds = seconds
        }

        var hold: TimeInterval {
            lock.lock()
            defer { lock.unlock() }
            return holdSeconds
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
            let hold = TTPUpdateRetryTests.updateResponses.hold
            if hold > 0 {
                Thread.sleep(forTimeInterval: hold)
            }
            status = TTPUpdateRetryTests.updateResponses.next()
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
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!,
            data
        )
    }
}
