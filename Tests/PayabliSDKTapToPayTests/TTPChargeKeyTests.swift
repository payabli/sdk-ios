import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest
#if canImport(PayabliCardReaderCore)
    @testable import PayabliCardReaderCore
#endif

/// Which key a charge's opening sends, when the charge keeps it, and what a refused resend reports.
@available(iOS 16.7, *)
@MainActor
final class TTPChargeKeyTests: XCTestCase {
    static let wire = Wire()
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

    func testAResendTheServiceAnsweredRestartsItsKeysClock() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        clock.advance(by: .seconds(180))
        Self.wire.initiateNotApproved = true
        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }
        Self.wire.initiateNotApproved = false
        clock.advance(by: .seconds(120))

        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(Self.wire.keys[2], Self.wire.keys[0], "a resend the service answered did not restart the clock")
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

    func testAnApprovalWhoseCloseFailsKeepsTheKey() async throws {
        let (ttp, _) = try await makeReadyTTP()
        Self.wire.updateFails = true
        let unclosed = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.updateFails = false

        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)

        XCTAssertEqual(unclosed?.capture, .charged)
        XCTAssertEqual(Self.wire.keys[1], Self.wire.keys[0], "a retry after a charged card went out under a new key")
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

    func testAFailedTapTheProcessorNeverSawReportsThePaymentNotTakenOnAFreshKey() async throws {
        let (ttp, _) = try await makeReadyTTP(readFailure: PayabliTTPError.nfcFailed(reason: "tap failed"))
        Self.wire.updateRefusal = Self.processorHasNoRecord

        let notTaken = await failure { try await ttp.charge(paymentDetails: Self.details) }

        XCTAssertEqual(notTaken?.type, .paymentNotTaken)
        XCTAssertEqual(notTaken?.code, 3035)
        XCTAssertEqual(notTaken?.category, .retryLater)
        XCTAssertEqual(notTaken?.capture, .notCharged)
        XCTAssertEqual(notTaken?.paymentTransId, "TXN-KEY")
    }

    func testAUserDismissalTheProcessorNeverSawReportsThePaymentNotTaken() async throws {
        let dismissal = "\(PayabliTTPError.cancellationReasonPrefix) user dismissed Tap to Pay sheet"
        let (ttp, _) = try await makeReadyTTP(readFailure: PayabliTTPError.nfcFailed(reason: dismissal))

        let cancelled = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.updateRefusal = Self.processorHasNoRecord
        let notTaken = await failure { try await ttp.charge(paymentDetails: Self.details) }

        XCTAssertEqual(cancelled?.type, .userCancelled)
        XCTAssertEqual(cancelled?.code, 1015)
        XCTAssertEqual(notTaken?.type, .paymentNotTaken)
        XCTAssertEqual(notTaken?.code, 3035)
        XCTAssertEqual(notTaken?.capture, .notCharged)
        XCTAssertEqual(notTaken?.paymentTransId, "TXN-KEY")
    }

    func testAFailedTapWhoseCloseAnswersAnythingElseStaysTheTapNotCompleted() async throws {
        let (ttp, _) = try await makeReadyTTP(readFailure: PayabliTTPError.nfcFailed(reason: "tap failed"))

        Self.wire.updateFails = true
        let serverFailure = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.updateFails = false
        Self.wire.updateRefusal = "The transaction was refused for another reason"
        let otherRefusal = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.updateRefusal = nil
        let landed = await failure { try await ttp.charge(paymentDetails: Self.details) }

        for reported in [serverFailure, otherRefusal, landed] {
            XCTAssertEqual(reported?.type, .tapNotCompleted)
            XCTAssertEqual(reported?.code, 3018)
            XCTAssertEqual(reported?.capture, .unknown)
        }
    }

    func testAFailedTapTheProcessorNeverSawStaysUnknownOnAResentKey() async throws {
        let (ttp, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        provider.readingResult = .failure(PayabliTTPError.nfcFailed(reason: "tap failed"))
        Self.wire.updateRefusal = Self.processorHasNoRecord

        let resent = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }
        Self.wire.updateRefusal = nil

        XCTAssertEqual(resent?.type, .tapNotCompleted)
        XCTAssertEqual(resent?.code, 3018)
        XCTAssertEqual(resent?.capture, .unknown)
        XCTAssertEqual(resent?.paymentTransId, "TXN-KEY")
    }

    func testAReaderGoneBeforeTheReadWhoseCloseLandsSettlesAFreshKey() async throws {
        let (ttp, provider) = try await makeReadyTTP(readFailure: PayabliTTPError.readerSessionExpired(capture: .notCharged))

        let expired = await failure { try await ttp.charge(paymentDetails: Self.details) }
        provider.readingResult = Self.read(.approved)
        try await ttp.initialize()
        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)

        XCTAssertEqual(expired?.type, .readerSessionExpired)
        XCTAssertEqual(expired?.capture, .notCharged)
        XCTAssertNotEqual(Self.wire.keys[1], Self.wire.keys[0], "the key outlived a charge that took nothing")
    }

    func testAReaderGoneBeforeTheReadWhoseCloseFindsNoRecordStaysTheSessionsExpiry() async throws {
        let (ttp, provider) = try await makeReadyTTP(readFailure: PayabliTTPError.readerSessionExpired(capture: .notCharged))
        Self.wire.updateRefusal = Self.processorHasNoRecord

        let expired = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.updateRefusal = nil
        provider.readingResult = Self.read(.approved)
        try await ttp.initialize()
        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)

        XCTAssertEqual(expired?.type, .readerSessionExpired)
        XCTAssertEqual(expired?.code, 3017)
        XCTAssertEqual(expired?.capture, .notCharged)
        XCTAssertEqual(expired?.paymentTransId, "TXN-KEY")
        XCTAssertNotEqual(Self.wire.keys[1], Self.wire.keys[0], "the key outlived a charge that took nothing")
    }

    #if canImport(PayabliCardReaderCore)
        /// The card reader's refusal to read without a session, rebuilt as the charge's own failure.
        func testTheCardReadersRefusalWithoutASessionExpiresTheSessionAndReleasesAFreshKey() async throws {
            let reader = FiservTTPReader(config: FiservTTPConfig(
                secretKey: "s", apiKey: "a", environment: .Sandbox, currencyCode: "USD", merchantId: "m",
                merchantName: "n", merchantCategoryCode: "5999", terminalId: "t", terminalProfileId: "p"
            ))
            guard case let .failure(refusal) = try await reader.readCard(
                for: 1, currencyCode: "USD", transactionType: .purchase
            ) else { return XCTFail("expected the read to be refused") }
            let chargeFailure = FiservTTPCardReaderError(
                title: "Charges", localizedDescription: refusal.localizedDescription, underlying: refusal
            )
            let (ttp, provider) = try await makeReadyTTP(readFailure: FiservCardReader.mapReadError(chargeFailure))

            let expired = await failure { try await ttp.charge(paymentDetails: Self.details) }
            let landed = ttp.sessionState
            provider.readingResult = Self.read(.approved)
            try await ttp.initialize()
            _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)

            XCTAssertEqual(expired?.code, 3017)
            XCTAssertEqual(expired?.capture, .notCharged)
            XCTAssertEqual(landed, .sessionExpired)
            XCTAssertNotEqual(Self.wire.keys[1], Self.wire.keys[0], "the key outlived a charge that took nothing")
        }
    #endif

    func testAReaderGoneBeforeTheReadKeepsAResentKey() async throws {
        let (ttp, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        provider.readingResult = .failure(PayabliTTPError.readerSessionExpired(capture: .notCharged))

        let expired = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }
        try await ttp.initialize()
        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(expired?.type, .readerSessionExpired)
        XCTAssertEqual(expired?.capture, .unknown, "a resent key names an earlier charge whose outcome is unknown")
        XCTAssertEqual(Set(Self.wire.keys).count, 1, "the resent key was settled by a charge that read no card")
    }

    func testAnIndeterminateReadsNoRecordCloseReportsThePaymentNotClosedAndKeepsTheKey() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        Self.wire.updateRefusal = Self.processorHasNoRecord

        let unclosed = await failure { try await ttp.charge(paymentDetails: Self.details) }
        Self.wire.updateRefusal = nil

        XCTAssertEqual(unclosed?.type, .paymentNotClosed)
        XCTAssertEqual(unclosed?.code, 3022)
        XCTAssertEqual(unclosed?.capture, .unknown)
        XCTAssertEqual(unclosed?.paymentTransId, "TXN-KEY")

        _ = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(Self.wire.keys[1], Self.wire.keys[0], "the indeterminate read's close settled the key")
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

    static let details = PayabliTTPPaymentDetails(amount: 1, currency: "USD")

    private static let processorHasNoRecord = "Unable to locate the transaction with the payment processor"

    static func read(_ outcome: CardReadOutcome) -> Result<CardReadResult, Error> {
        .success(CardReadResult(provider: "mock", encryptedPayload: Data(), outcome: outcome))
    }

    func makeReadyTTP(
        outcome: CardReadOutcome = .approved,
        readFailure: Error? = nil,
        store: ChargeKeyStore? = nil,
        attestation: MockDeviceAttestationService = MockDeviceAttestationService()
    ) async throws -> (PayabliTTP, MockTapToPayProvider) {
        StubURLProtocol.handler = Self.stubHandler
        let provider = MockTapToPayProvider()
        provider.readingResult = readFailure.map { .failure($0) } ?? Self.read(outcome)
        let ttp = PayabliTTP(
            config: try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession(),
            chargeKeys: store ?? ChargeKeyStore(now: { [clock] in clock.now })
        )
        try await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .ready, "the fixture itself is broken if this fails")
        return (ttp, provider)
    }

    func failure(_ work: () async throws -> some Any) async -> TapToPayError? {
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
}
