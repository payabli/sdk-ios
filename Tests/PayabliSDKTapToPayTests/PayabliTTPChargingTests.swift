import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// What `sessionState` reports while a charge runs, from the state a host reads.
@MainActor
final class PayabliTTPChargingTests: XCTestCase {
    private static let paymentTransId = "TXN-CHARGING"
    private static let responses = ScriptedResponses()

    private let opening = PayabliTTPSessionState.charging(activity: .opening)
    private let waiting = PayabliTTPSessionState.charging(activity: .waitingForCard)
    private let closing = PayabliTTPSessionState.charging(activity: .closing)

    override func tearDown() {
        StubURLProtocol.handler = nil
        Self.responses.reset()
        super.tearDown()
    }

    // MARK: - How a charge moves

    func testAnApprovedChargeOpensWaitsClosesAndEndsReady() async throws {
        let (ttp, _) = try await makeReadyTTP()
        let seen = record(ttp)

        let result = try await charge(ttp)

        XCTAssertEqual(result.paymentTransId, Self.paymentTransId)
        XCTAssertEqual(seen.states, [opening, waiting, closing, .ready])
    }

    func testARefusedCardEndsReady() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .declined)
        let seen = record(ttp)

        let failure = await chargeFailure(ttp)

        XCTAssertEqual(failure?.type, .cardDeclined)
        XCTAssertEqual(seen.states, [opening, waiting, closing, .ready])
    }

    func testAnOutcomeThatIsNeitherEndsReady() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        let seen = record(ttp)

        let failure = await chargeFailure(ttp)

        XCTAssertEqual(failure?.type, .paymentOutcomeUnknown)
        XCTAssertEqual(seen.states, [opening, waiting, closing, .ready])
    }

    func testAFailedCloseEndsReady() async throws {
        let (ttp, _) = try await makeReadyTTP()
        Self.responses.updateStatus = 500
        let seen = record(ttp)

        _ = await chargeFailure(ttp)

        XCTAssertEqual(seen.states, [opening, waiting, closing, .ready])
    }

    /// A refused opening never asks for a card, so the charge ends without waiting or closing.
    func testARefusedOpeningEndsReadyWithoutWaiting() async throws {
        let (ttp, provider) = try await makeReadyTTP()
        Self.responses.initiateStatus = 500
        let seen = record(ttp)

        _ = await chargeFailure(ttp)

        XCTAssertEqual(seen.states, [opening, .ready])
        XCTAssertEqual(provider.startReadingCalls, 0)
    }

    func testAFailedTapClosesAndEndsReady() async throws {
        let (ttp, _) = try await makeReadyTTP(readFailure: PayabliTTPError.nfcFailed(reason: "cardReadFailed"))
        let seen = record(ttp)

        _ = await chargeFailure(ttp)

        XCTAssertEqual(seen.states, [opening, waiting, closing, .ready])
    }

    /// A read that finds the reader session spent closes the payment, then expires the session, and nothing
    /// after it moves the state back.
    func testADeadReaderEndsTheChargeExpired() async throws {
        let (ttp, _) = try await makeReadyTTP(
            readFailure: PayabliTTPError.nfcFailed(reason: "Charges: readerSessionExpired")
        )
        let seen = record(ttp)

        _ = await chargeFailure(ttp)

        XCTAssertEqual(seen.states, [opening, waiting, closing, .sessionExpired])
        XCTAssertEqual(ttp.sessionState, .sessionExpired)
    }

    /// A ready session whose stored device record is gone sends nothing and lands where setting the
    /// device up again repairs it, so a retry is not sent back to the same line.
    func testALostDeviceRecordFailsTheSessionAndSendsNothing() async throws {
        let (ttp, provider, attestation) = try await makeReadyTTPWithAttestation()
        attestation.cachedDeviceId = nil
        let seen = record(ttp)

        let failure = await chargeFailure(ttp)

        XCTAssertEqual(failure?.type, .deviceSetupRequired)
        XCTAssertEqual(failure?.capture, .notCharged)
        XCTAssertNil(failure?.paymentTransId)
        XCTAssertEqual(seen.states, [opening, .failed(reason: .deviceSetupRequired)])
        XCTAssertFalse(ttp.isReady)
        XCTAssertEqual(provider.startReadingCalls, 0)
        XCTAssertEqual(Self.responses.initiateCalls, 0)
    }

    // MARK: - While the reader waits

    func testTheSessionIsNotReadyWhileTheReaderWaits() async throws {
        let (ttp, provider) = try await makeReadyTTP()
        let during = Snapshot()
        provider.whileReading = { [weak ttp] in
            during.state = ttp?.sessionState
            during.isReady = ttp?.isReady
        }

        _ = try await charge(ttp)

        XCTAssertEqual(during.state, waiting)
        XCTAssertEqual(during.isReady, false)
        XCTAssertTrue(ttp.isReady)
    }

    func testASecondChargeIsRefusedWhileOneHoldsTheReader() async throws {
        let (ttp, provider) = try await makeReadyTTP()
        let during = Snapshot()
        provider.whileReading = { [weak ttp] in
            guard let ttp else { return }
            do {
                _ = try await ttp.charge(type: .sale, paymentDetails: PayabliTTPPaymentDetails(amount: 1))
            } catch {
                during.refusal = (error as? TapToPayError)?.type
            }
        }

        _ = try await charge(ttp)

        XCTAssertEqual(during.refusal, .terminalNotReady)
        XCTAssertEqual(provider.startReadingCalls, 1)
        XCTAssertEqual(ttp.sessionState, .ready)
    }

    /// An `initialize()` during the tap rebuilds the session, and the charge ending afterwards leaves what
    /// it built alone.
    func testASessionRebuiltDuringTheTapIsKept() async throws {
        let (ttp, provider) = try await makeReadyTTP()
        provider.whileReading = { [weak ttp] in
            try? await ttp?.initialize()
        }
        let seen = record(ttp)

        let result = try await charge(ttp)

        XCTAssertEqual(result.paymentTransId, Self.paymentTransId)
        XCTAssertEqual(seen.states.prefix(3), [opening, waiting, .idle])
        XCTAssertFalse(seen.states.contains(closing), "the closing write landed on a session the charge no longer held")
        XCTAssertEqual(ttp.sessionState, .ready)
    }

    func testAPromptFromAReplacedReaderIsDropped() async throws {
        let (ttp, provider) = try await makeReadyTTP()
        let during = Snapshot()
        provider.whileReading = { [weak ttp] in
            guard let ttp, let current = ttp.preparedReader else { return }
            ttp.handleReaderEvent(.cardDetected, from: current - 1)
            during.state = ttp.sessionState
        }

        _ = try await charge(ttp)

        XCTAssertEqual(during.state, waiting)
    }

    func testReinitializingDuringATapLeavesTheChargeAlone() async throws {
        let (ttp, provider) = try await makeReadyTTP()
        let during = Snapshot()
        provider.whileReading = { [weak ttp] in
            do {
                try await ttp?.reinitializeIfNeeded()
            } catch {
                during.refusal = (error as? TapToPayError)?.type
            }
            during.state = ttp?.sessionState
        }

        _ = try await charge(ttp)

        XCTAssertNil(during.refusal)
        XCTAssertEqual(during.state, waiting)
    }

    func testTheReadersPromptsReportOnTheState() async throws {
        let (ttp, provider) = try await makeReadyTTP()
        provider.whileReading = { [weak provider] in
            for event in [
                TapToPayReaderEvent.cardDetected, .notReady, .pinEntryRequested, .pinEntryCompleted,
                .cardReadRetryRequested, .promptDismissed, .cardRemovalRequested
            ] {
                provider?.emitReaderEvent(event)
            }
        }
        let seen = record(ttp)

        _ = try await charge(ttp)

        XCTAssertEqual(seen.states, [
            opening, waiting,
            .charging(activity: .cardDetected),
            .charging(activity: .pinEntryRequested),
            .charging(activity: .pinEntryCompleted),
            .charging(activity: .cardReadRetryRequested),
            .charging(activity: .readerPromptDismissed),
            .charging(activity: .cardRemovalRequested),
            closing, .ready
        ])
    }

    func testAnObjectiveCHostReadsTheActivityWhenTold() async throws {
        let (ttp, _) = try await makeReadyTTP()
        var read: [NSNumber?] = []
        let observation = ttp.addSessionStateObserver { read.append(ttp.chargeActivity) }

        _ = try await charge(ttp)
        observation.cancel()

        XCTAssertEqual(read, [
            NSNumber(value: TapToPayChargeActivity.opening.rawValue),
            NSNumber(value: TapToPayChargeActivity.waitingForCard.rawValue),
            NSNumber(value: TapToPayChargeActivity.closing.rawValue),
            nil
        ])
    }

    // MARK: - Fixture

    private final class Recording {
        var states: [PayabliTTPSessionState] = []
        var observation: TapToPaySessionStateObservation?
    }

    private final class Snapshot: @unchecked Sendable {
        var state: PayabliTTPSessionState?
        var isReady: Bool?
        var refusal: PayabliErrorType?
    }

    /// Every state the session publishes from here on, in order.
    private func record(_ ttp: PayabliTTP) -> Recording {
        let recording = Recording()
        recording.observation = ttp.addSessionStateObserver { [weak ttp, recording] in
            if let state = ttp?.sessionState {
                recording.states.append(state)
            }
        }
        return recording
    }

    final class ScriptedResponses: @unchecked Sendable {
        private let lock = NSLock()
        private var initiate = 200
        private var update = 200
        private var initiates = 0

        var initiateCalls: Int {
            lock.withLock { initiates }
        }

        func countInitiate() {
            lock.withLock { initiates += 1 }
        }

        var initiateStatus: Int {
            get { lock.withLock { initiate } }
            set { lock.withLock { initiate = newValue } }
        }

        var updateStatus: Int {
            get { lock.withLock { update } }
            set { lock.withLock { update = newValue } }
        }

        func reset() {
            lock.withLock {
                initiate = 200
                update = 200
                initiates = 0
            }
        }
    }

    private func makeReadyTTP(
        outcome: CardReadOutcome = .approved,
        readFailure: Error? = nil
    ) async throws -> (PayabliTTP, MockTapToPayProvider) {
        let (ttp, provider, _) = try await makeReadyTTPWithAttestation(outcome: outcome, readFailure: readFailure)
        return (ttp, provider)
    }

    private func makeReadyTTPWithAttestation(
        outcome: CardReadOutcome = .approved,
        readFailure: Error? = nil
    ) async throws -> (PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService) {
        StubURLProtocol.handler = Self.stubHandler
        let provider = MockTapToPayProvider()
        provider.readingResult = readFailure.map { .failure($0) }
            ?? .success(CardReadResult(provider: "mock", encryptedPayload: Data(), outcome: outcome))
        let attestation = MockDeviceAttestationService()
        let ttp = PayabliTTP(
            config: try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        try await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .ready, "the fixture itself is broken if this fails")
        return (ttp, provider, attestation)
    }

    private func charge(_ ttp: PayabliTTP) async throws -> TransactionResult {
        try await ttp.charge(type: .sale, paymentDetails: PayabliTTPPaymentDetails(amount: 1, currency: "USD"))
    }

    private func chargeFailure(_ ttp: PayabliTTP) async -> TapToPayError? {
        do {
            _ = try await charge(ttp)
            XCTFail("expected the charge to fail")
        } catch let failure as TapToPayError {
            return failure
        } catch {
            XCTFail("expected a TapToPayError, got \(error)")
        }
        return nil
    }

    private static let stubHandler: StubURLProtocol.Handler = { request in
        let path = request.url?.path ?? ""
        var status = 200
        let body: [String: Any]
        if path.contains("/MoneyIn/initiate") {
            PayabliTTPChargingTests.responses.countInitiate()
            status = PayabliTTPChargingTests.responses.initiateStatus
            body = ["code": "A01", "data": ["paymentTransId": PayabliTTPChargingTests.paymentTransId]]
        } else if path.contains("/MoneyIn/update/") {
            status = PayabliTTPChargingTests.responses.updateStatus
            body = ["code": "A01", "data": ["paymentTransId": PayabliTTPChargingTests.paymentTransId]]
        } else {
            body = [
                "responseCode": 1,
                "isSuccess": true,
                "responseData": [
                    "credentials": ["secretKey": "s", "apiKey": "a", "merchantId": "m", "terminalId": "t"]
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
