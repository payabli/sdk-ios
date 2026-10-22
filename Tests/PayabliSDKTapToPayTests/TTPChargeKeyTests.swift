import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// Which key a charge's opening sends, when the charge keeps it, and what a refused resend reports.
@available(iOS 16.7, *)
@MainActor
final class TTPChargeKeyTests: XCTestCase {
    private static let wire = Wire()
    private let clock = ManualChargeClock()

    override func tearDown() {
        StubURLProtocol.handler = nil
        Self.wire.reset()
        super.tearDown()
    }

    // MARK: - Which key goes out

    func testEveryOpeningSendsAKey() async throws {
        let (ttp, _) = try await makeReadyTTP()

        _ = try await ttp.charge(paymentDetails: Self.details)

        XCTAssertEqual(Self.wire.keys.count, 1)
        XCTAssertNotNil(UUID(uuidString: Self.wire.keys[0]), "the key is a v4 UUID")
    }

    func testADeclaredRetryResendsTheUnresolvedChargesKeyAndANewPaymentMintsItsOwn() async throws {
        let (ttp, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        provider.readingResult = Self.read(.approved)

        _ = try await ttp.charge(paymentDetails: Self.details)
        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)

        let keys = Self.wire.keys
        XCTAssertEqual(keys.count, 3)
        XCTAssertNotEqual(keys[1], keys[0], "a new payment took the unresolved charge's key")
        XCTAssertEqual(keys[2], keys[0], "the declared retry did not resend the unresolved charge's key")
    }

    func testAnObjectiveCRetryResendsTheUnresolvedChargesKey() async throws {
        let (ttp, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        provider.readingResult = Self.read(.approved)
        let request = PayabliTTPChargeRequestObjC(
            paymentDetails: PayabliTTPPaymentDetailsObjC(
                amount: 1, serviceFee: 0, currency: "USD", paymentDescription: nil
            )
        )
        request.attempt = .retry

        let done = expectation(description: "charge")
        ttp.charge(request) { _, _ in done.fulfill() }
        await fulfillment(of: [done], timeout: 5)

        XCTAssertEqual(Self.wire.keys.count, 2)
        XCTAssertEqual(Self.wire.keys[1], Self.wire.keys[0])
    }

    func testARetryDescribingAnotherPaymentIsRefusedBeforeAnythingIsSent() async throws {
        let (ttp, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        provider.readingResult = Self.read(.approved)

        let refused = await failure {
            try await ttp.charge(paymentDetails: PayabliTTPPaymentDetails(amount: 2, currency: "USD"), attempt: .retry)
        }

        XCTAssertEqual(refused?.type, .retryNotSamePayment)
        XCTAssertEqual(refused?.capture, .notCharged)
        XCTAssertEqual(Self.wire.keys.count, 1, "the refused retry was sent")
        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)
        XCTAssertEqual(Self.wire.keys.last, Self.wire.keys.first, "the held key did not stay")
    }

    // MARK: - A resend refused as a repeat

    func testAResendRefusedAsARepeatReportsTheEarlierChargeNotFinished() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.initiateStatus = 409

        let refused = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(refused?.type, .chargeNotFinished)
        XCTAssertEqual(refused?.code, 3034)
        XCTAssertEqual(refused?.category, .outcomeUnknown)
        XCTAssertEqual(refused?.capture, .unknown)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }
        XCTAssertEqual(Set(Self.wire.keys).count, 1, "the refused resend released its key")
        XCTAssertEqual(ttp.sessionState, .ready)
    }

    func testAResendRefusedAsADuplicateSaleStaysAConflict() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.initiateStatus = 409
        Self.wire.conflictIsDuplicateSale = true

        let refused = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(refused?.type, .conflict)
        XCTAssertEqual(refused?.code, 1011)
        XCTAssertEqual(refused?.capture, .unknown, "a resent key never reports not charged")
    }

    func testAFreshKeyRefusedAsARepeatStaysAConflictAndIsReleased() async throws {
        let (ttp, _) = try await makeReadyTTP()
        Self.wire.initiateStatus = 409

        let refused = await failure { try await ttp.charge(paymentDetails: Self.details) }

        XCTAssertEqual(refused?.type, .conflict)
        XCTAssertEqual(refused?.code, 1011)
        Self.wire.initiateStatus = 200
        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)
        XCTAssertNotEqual(Self.wire.keys[1], Self.wire.keys[0])
    }

    func testARefusedResendDoesNotRestartItsKeysClock() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        clock.advance(by: .seconds(180))
        Self.wire.initiateStatus = 409
        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }
        clock.advance(by: .seconds(120))
        Self.wire.initiateStatus = 200

        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertNotEqual(Self.wire.keys[2], Self.wire.keys[0], "a key past the bound was resent")
    }

    func testAResendWithdrawnBeforeItLeftDoesNotRestartItsKeysClock() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        clock.advance(by: .seconds(180))
        let withdrawn = Task { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }
        withdrawn.cancel()
        _ = await withdrawn.result
        XCTAssertEqual(Self.wire.keys.count, 1, "the withdrawn resend left the device")
        clock.advance(by: .seconds(120))

        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertNotEqual(Self.wire.keys.last, Self.wire.keys.first, "the withdrawn resend restarted the clock")
    }

    // MARK: - When a charge keeps its key

    func testAnApprovalThatClosesSettlesTheKey() async throws {
        let (ttp, _) = try await makeReadyTTP()
        _ = try await ttp.charge(paymentDetails: Self.details)

        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)

        XCTAssertNotEqual(Self.wire.keys[1], Self.wire.keys[0])
    }

    func testADeclineSettlesTheKey() async throws {
        let (ttp, provider) = try await makeReadyTTP(outcome: .declined)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        provider.readingResult = Self.read(.approved)

        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)

        XCTAssertNotEqual(Self.wire.keys[1], Self.wire.keys[0])
    }

    func testAnUnknownOutcomeKeepsTheKey() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)

        let unknown = await failure { try await ttp.charge(paymentDetails: Self.details) }
        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(unknown?.capture, .unknown)
        XCTAssertEqual(Self.wire.keys[1], Self.wire.keys[0])
    }

    func testAnExpiredKeyIsNotResent() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        clock.advance(by: payabliIdempotencyKeyMaxAge)

        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertNotEqual(Self.wire.keys[1], Self.wire.keys[0])
    }

    func testAResendNeverReportsNotCharged() async throws {
        let (ttp, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        provider.readingResult = Self.read(.declined)

        let declined = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(declined?.type, .cardDeclined)
        XCTAssertEqual(declined?.capture, .unknown)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }
        XCTAssertEqual(Set(Self.wire.keys).count, 1, "the resent key was settled by a later charge's answer")
    }

    func testAFailedTapTheProcessorNeverSawSettlesAFreshKey() async throws {
        let (ttp, provider) = try await makeReadyTTP(readFailure: PayabliTTPError.nfcFailed(reason: "tap failed"))
        Self.wire.updateRefusal = Self.processorHasNoRecord
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        provider.readingResult = Self.read(.approved)
        Self.wire.updateRefusal = nil

        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)

        XCTAssertNotEqual(Self.wire.keys[1], Self.wire.keys[0])
    }

    func testAFailedTapWhoseCloseLandsKeepsTheKey() async throws {
        let (ttp, _) = try await makeReadyTTP(readFailure: PayabliTTPError.nfcFailed(reason: "tap failed"))
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }

        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(Self.wire.keys[1], Self.wire.keys[0])
    }

    func testAResentFailedTapTheProcessorNeverSawKeepsTheKey() async throws {
        let (ttp, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        provider.readingResult = .failure(PayabliTTPError.nfcFailed(reason: "tap failed"))
        Self.wire.updateRefusal = Self.processorHasNoRecord
        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }
        Self.wire.updateRefusal = nil

        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(Set(Self.wire.keys).count, 1)
    }

    func testAnOpeningThatFailsHoldsNoKeyAndLeavesTheEarlierOneClaimable() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.initiateStatus = 500

        let failed = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.initiateStatus = 200
        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(failed?.capture, .notCharged)
        XCTAssertEqual(Self.wire.keys[2], Self.wire.keys[0], "the failed opening dropped the earlier key")
    }

    func testANewerChargeThatSettlesLeavesTheOlderKeyClaimable() async throws {
        let (ttp, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        provider.readingResult = Self.read(.approved)
        _ = try await ttp.charge(paymentDetails: Self.details)

        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)

        XCTAssertEqual(Self.wire.keys[2], Self.wire.keys[0])
    }

    func testFourUnknownChargesOnOneEntryPointLeaveRoomForAFifth() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        for _ in 0 ..< 4 {
            _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        }

        let fifth = await failure { try await ttp.charge(paymentDetails: Self.details) }

        XCTAssertEqual(fifth?.type, .paymentOutcomeUnknown)
        XCTAssertEqual(Self.wire.keys.count, 5)
    }

    func testAChargeForAFifthEntryPointIsRefusedBeforeAnythingIsSent() async throws {
        let store = ChargeKeyStore(now: { [clock] in clock.now })
        for entry in ["a", "b", "c", "d"] {
            let held = try store.reserve(
                entry: entry,
                environment: .sandbox,
                attempt: .newPayment,
                description: ChargeDescription(paymentDetails: Self.details, invoice: PayabliTTPInvoiceData())
            )
            store.supersede(entry: entry, environment: .sandbox, key: held.key, arrivedAt: held.reservedAt)
        }
        let (ttp, _) = try await makeReadyTTP(store: store)

        let refused = await failure { try await ttp.charge(paymentDetails: Self.details) }

        XCTAssertEqual(refused?.type, .tooManyOpenCharges)
        XCTAssertEqual(refused?.code, 3030)
        XCTAssertEqual(Self.wire.keys.count, 0)
        XCTAssertEqual(ttp.sessionState, .ready)
    }

    // MARK: - Helpers

    private static let details = PayabliTTPPaymentDetails(amount: 1, currency: "USD")

    private static let processorHasNoRecord = "Unable to locate the transaction with the payment processor"

    private static func read(_ outcome: CardReadOutcome) -> Result<CardReadResult, Error> {
        .success(CardReadResult(provider: "mock", encryptedPayload: Data(), outcome: outcome))
    }

    private func makeReadyTTP(
        outcome: CardReadOutcome = .approved,
        readFailure: Error? = nil,
        store: ChargeKeyStore? = nil
    ) async throws -> (PayabliTTP, MockTapToPayProvider) {
        StubURLProtocol.handler = Self.stubHandler
        let provider = MockTapToPayProvider()
        provider.readingResult = readFailure.map { .failure($0) } ?? Self.read(outcome)
        let ttp = PayabliTTP(
            config: try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
            provider: provider,
            attestation: MockDeviceAttestationService(),
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession(),
            chargeKeys: store ?? ChargeKeyStore(now: { [clock] in clock.now })
        )
        try await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .ready, "the fixture itself is broken if this fails")
        return (ttp, provider)
    }

    private func failure(_ work: () async throws -> some Any) async -> TapToPayError? {
        do {
            _ = try await work()
            XCTFail("expected the charge to fail")
        } catch let failure as TapToPayError {
            return failure
        } catch {
            XCTFail("expected a TapToPayError, got \(error)")
        }
        return nil
    }

    final class Wire: @unchecked Sendable {
        private let lock = NSLock()
        private var sentKeys: [String] = []
        private var initiate = 200
        private var refusal: String?
        private var duplicateSale = false

        var keys: [String] {
            lock.withLock { sentKeys }
        }

        var initiateStatus: Int {
            get { lock.withLock { initiate } }
            set { lock.withLock { initiate = newValue } }
        }

        var updateRefusal: String? {
            get { lock.withLock { refusal } }
            set { lock.withLock { refusal = newValue } }
        }

        var conflictIsDuplicateSale: Bool {
            get { lock.withLock { duplicateSale } }
            set { lock.withLock { duplicateSale = newValue } }
        }

        func record(_ key: String?) {
            lock.withLock { sentKeys.append(key ?? "<none>") }
        }

        func reset() {
            lock.withLock {
                sentKeys = []
                initiate = 200
                refusal = nil
                duplicateSale = false
            }
        }
    }

    private static let stubHandler: StubURLProtocol.Handler = { request in
        let path = request.url?.path ?? ""
        var status = 200
        var contentType = "application/json"
        let data: Data
        if path.contains("/MoneyIn/initiate") {
            wire.record(request.value(forHTTPHeaderField: "idempotencyKey"))
            status = wire.initiateStatus
            if status == 409, wire.conflictIsDuplicateSale {
                data = try JSONSerialization.data(withJSONObject: ["isSuccess": false, "responseText": "Duplicated transaction"])
            } else if status == 409 {
                contentType = "text/plain"
                data = Data("Duplicated idempotencyKey".utf8)
            } else {
                data = try JSONSerialization.data(withJSONObject: ["code": "A01", "data": ["paymentTransId": "TXN-KEY"]])
            }
        } else if path.contains("/MoneyIn/update/") {
            if let refusal = wire.updateRefusal {
                status = 400
                data = try JSONSerialization.data(withJSONObject: ["title": "Bad Request", "status": 400, "detail": refusal])
            } else {
                data = try JSONSerialization.data(withJSONObject: ["code": "A01", "data": ["paymentTransId": "TXN-KEY"]])
            }
        } else {
            data = try JSONSerialization.data(withJSONObject: [
                "responseCode": 1,
                "isSuccess": true,
                "responseData": [
                    "credentials": ["secretKey": "s", "apiKey": "a", "merchantId": "m", "terminalId": "t"]
                ],
                "paymentToken": "payment_tok"
            ])
        }
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType]
            )!,
            data
        )
    }
}
