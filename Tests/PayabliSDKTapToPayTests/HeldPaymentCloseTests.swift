@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// `closeCapturedCharge` for a payment whose card was read and whose close was not confirmed: what it settles, what a
/// failure reports, and which terminals share it.
@available(iOS 16.7, *)
@MainActor
final class HeldPaymentCloseTests: XCTestCase {
    private static let wire = CloseWire()
    private static let opened = "TXN-OPENED"
    private static let sale = PayabliTTPPaymentDetails(amount: 1, currency: .usd)
    /// One of each store for every terminal in a case, as the process has one.
    private let keys = ChargeKeyStore()
    private let held = HeldPayments()

    override func setUp() {
        super.setUp()
        Self.wire.reset()
        StubURLProtocol.handler = Self.wire.handle
    }

    override func tearDown() {
        Self.wire.release()
        StubURLProtocol.handler = nil
        Self.wire.reset()
        super.tearDown()
    }

    // MARK: - A close that lands

    func testAHeldPaymentIsClosedWithoutASecondTapOrASecondOpeningAndItsKeySettles() async throws {
        let (terminal, provider) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .approved)

        Self.wire.script(updates: [200])
        try await terminal.closeCapturedCharge(paymentTransId: Self.opened)

        let closes = Self.wire.closes(of: Self.opened)
        XCTAssertEqual(closes.last?.body, Data("{}".utf8), "a held close sent what the reader returned")
        XCTAssertEqual(provider.startReadingCalls, 1, "the close asked for a second tap")
        XCTAssertEqual(Self.wire.openings, 1, "the close opened a second payment")
        XCTAssertFalse(keyIsHeld(), "a definite payment's key outlived its confirmed close")
    }

    func testAHeldPaymentOnceClosedIsNoLongerHeld() async throws {
        let (terminal, _) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .approved)
        Self.wire.script(updates: [200])
        try await terminal.closeCapturedCharge(paymentTransId: Self.opened)

        Self.wire.script(updates: [500])
        let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }

        XCTAssertEqual(failure?.capture, .unknown, "the closed payment was still held")
    }

    func testAHeldPaymentWhoseOutcomeWasNeverDefiniteKeepsItsKeyWhenTheCloseLands() async throws {
        let (terminal, _) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .indeterminate)

        Self.wire.script(updates: [200])
        try await terminal.closeCapturedCharge(paymentTransId: Self.opened)

        XCTAssertTrue(keyIsHeld(), "the only handle on a payment that may have taken money was dropped")
    }

    /// The resent key names an earlier charge whose outcome was never known, so this approval does not settle it.
    func testAHeldApprovalUnderAResentKeyKeepsTheKeyWhenTheCloseLands() async throws {
        let (terminal, provider) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .indeterminate)
        provider.readingResult = .success(Self.read(.approved))
        _ = await Self.failure { _ = try await terminal.charge(paymentDetails: Self.sale, attempt: .retry) }

        Self.wire.script(updates: [200])
        try await terminal.closeCapturedCharge(paymentTransId: Self.opened)
        let keyOutlivedTheClose = keyIsHeld()
        Self.wire.script(updates: [500])
        let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }

        XCTAssertTrue(keyOutlivedTheClose, "a close under a resent key settled the earlier charge's key")
        XCTAssertEqual(failure?.capture, .unknown, "the closed payment was still held")
    }

    // MARK: - A close that fails

    func testAHeldCloseThatFailsReportsTheReadersCaptureAndStaysHeld() async throws {
        let (terminal, _) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .approved)

        let first = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }
        let second = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }

        XCTAssertEqual(first?.type, .paymentNotClosed)
        XCTAssertEqual(first?.paymentTransId, Self.opened)
        XCTAssertEqual(first?.capture, .charged)
        XCTAssertEqual(second?.capture, .charged, "a failed close dropped the held payment")
        XCTAssertTrue(keyIsHeld(), "a failed close settled the key")
    }

    func testAHeldDeclineWhoseCloseFailsIsNotCharged() async throws {
        let (terminal, _) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .declined)

        let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }

        XCTAssertEqual(failure?.capture, .notCharged)
    }

    /// The resent key names an earlier charge whose outcome was never known, so this decline says nothing about it.
    func testAHeldDeclineUnderAResentKeyWhoseCloseFailsIsUnknown() async throws {
        let (terminal, provider) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .indeterminate)
        provider.readingResult = .success(Self.read(.declined))
        _ = await Self.failure { _ = try await terminal.charge(paymentDetails: Self.sale, attempt: .retry) }

        let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }

        XCTAssertEqual(failure?.capture, .unknown)
    }

    /// The other close lands while this one waits to send again, so the payment is no longer held when this one fails.
    func testAHeldCloseThatFailsAfterAnotherCloseLandedIsUnknown() async throws {
        let (terminal, _) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .approved)
        let (waiting, _) = try await makeReadyTerminal(retryPolicy: Self.twoAttempts(apart: 0.5))
        Self.wire.reset()
        Self.wire.script(updates: [500, 200, 500])

        let failing = Task { await Self.failure { try await waiting.closeCapturedCharge(paymentTransId: Self.opened) } }
        await Self.wire.waitUntilAnUpdateArrives()
        try await terminal.closeCapturedCharge(paymentTransId: Self.opened)
        let failure = await failing.value

        XCTAssertEqual(Self.wire.updates.count, 3, "the closes did not overlap as scripted")
        XCTAssertEqual(failure?.capture, .unknown, "a failed close reported a payment another close had closed")
    }

    // MARK: - What holds it

    func testAPaymentHeldByOneTerminalIsClosedByAnotherForTheSameEntryPoint() async throws {
        let (first, _) = try await makeReadyTerminal()
        try await leaveHeld(on: first, read: .approved)
        let (second, _) = try await makeReadyTerminal()

        Self.wire.script(updates: [200])
        try await second.closeCapturedCharge(paymentTransId: Self.opened)

        XCTAssertFalse(keyIsHeld(), "the second terminal did not find the payment the first held")
    }

    func testEveryTerminalInTheProcessSharesOneStoreOfHeldPayments() throws {
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "token" })
        let terminal = PayabliTTP(
            session: PayabliSession(config: config, urlSession: StubURLProtocol.makeSession()),
            provider: MockTapToPayProvider(),
            attestation: MockDeviceAttestationService()
        )

        XCTAssertTrue(terminal.heldPayments === HeldPayments.process)
    }

    func testAClosedPaymentThatIsNotTheHeldOneLeavesTheHeldOneAndItsKey() async throws {
        let (terminal, _) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .approved)

        Self.wire.script(updates: [200])
        try await terminal.closeCapturedCharge(paymentTransId: "TXN-EARLIER")
        let keyOutlivedTheClose = keyIsHeld()
        Self.wire.script(updates: [500])
        let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }

        XCTAssertTrue(keyOutlivedTheClose, "closing another payment settled the held payment's key")
        XCTAssertEqual(failure?.capture, .charged, "closing another payment dropped the held one")
    }

    func testAPaymentHeldForOneEntryPointIsNotHeldForAnother() async throws {
        let (terminal, _) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .approved)
        let (other, _) = try await makeReadyTerminal(entryPoint: "another")

        let failure = await Self.failure { try await other.closeCapturedCharge(paymentTransId: Self.opened) }

        XCTAssertEqual(failure?.capture, .unknown)
    }

    func testAPaymentHeldInOneEnvironmentIsNeitherReportedNorClosedByAnother() async throws {
        let (terminal, _) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .approved)
        let (production, _) = try await makeReadyTerminal(environment: .production)

        let unheld = await Self.failure { try await production.closeCapturedCharge(paymentTransId: Self.opened) }
        Self.wire.script(updates: [200])
        try await production.closeCapturedCharge(paymentTransId: Self.opened)
        let keyOutlivedTheClose = keyIsHeld()
        Self.wire.script(updates: [500])
        let held = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }

        XCTAssertEqual(unheld?.capture, .unknown, "another environment's terminal reported the held capture")
        XCTAssertTrue(keyOutlivedTheClose, "a close in another environment settled the held payment's key")
        XCTAssertEqual(held?.capture, .charged, "a close in another environment dropped the held payment")
    }

    func testTheNextOpeningOnTheEntryPointDropsTheHeldPayment() async throws {
        let (terminal, provider) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .approved)
        provider.readingResult = .failure(PayabliTTPError.nfcFailed(reason: "read failed"))
        _ = await Self.failure { _ = try await terminal.charge(paymentDetails: Self.sale) }

        let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }

        XCTAssertEqual(failure?.capture, .unknown, "the payment the next opening replaced was still held")
    }

    func testAChargeWhoseCloseLandsHoldsNothing() async throws {
        let (terminal, _) = try await makeReadyTerminal()
        _ = try await terminal.charge(paymentDetails: Self.sale)

        Self.wire.script(updates: [500])
        let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }

        XCTAssertEqual(failure?.capture, .unknown)
    }

    /// The cancelled caller's close still lands, so the key settles and the payment is no longer held.
    func testACancelledHeldCloseStillSettlesWhatItsLandingAllows() async throws {
        let (terminal, _) = try await makeReadyTerminal()
        try await leaveHeld(on: terminal, read: .approved)
        // The charge's failed closes are recorded, so the wait below would return before this close is sent.
        Self.wire.reset()
        Self.wire.script(updates: [500, 200])
        Self.wire.holdUpdates()

        let closing = Task { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }
        await Self.wire.waitUntilAnUpdateArrives()
        closing.cancel()
        Self.wire.release()
        _ = try? await closing.value

        XCTAssertFalse(keyIsHeld(), "a cancelled caller stopped the close from settling the key")
    }

    // MARK: - Helpers

    /// Charges with a reader answering `outcome` and every close failing, so the payment is left held.
    private func leaveHeld(on terminal: PayabliTTP, read outcome: CardReadOutcome) async throws {
        let provider = try XCTUnwrap(terminal.provider as? MockTapToPayProvider)
        provider.readingResult = .success(Self.read(outcome))
        Self.wire.script(updates: [500])
        let failure = await Self.failure { _ = try await terminal.charge(paymentDetails: Self.sale) }
        XCTAssertEqual(failure?.paymentTransId, Self.opened, "the fixture itself is broken if this fails")
        Self.wire.script(updates: [500])
    }

    private func keyIsHeld() -> Bool {
        keys.holdsRetryOf(
            entry: "e",
            environment: .sandbox,
            description: ChargeDescription(paymentDetails: Self.sale, invoice: PayabliTTPInvoiceData())
        )
    }

    private static func read(_ outcome: CardReadOutcome) -> CardReadResult {
        CardReadResult(provider: "mock", encryptedPayload: Data(), outcome: outcome)
    }

    private func makeReadyTerminal(
        entryPoint: String = "e",
        environment: PayabliEnvironment = .sandbox,
        retryPolicy: RetryPolicy = noWait
    ) async throws -> (PayabliTTP, MockTapToPayProvider) {
        let provider = MockTapToPayProvider()
        provider.readingResult = .success(Self.read(.approved))
        let config = try PayabliConfig(entryPoint: entryPoint, environment: environment, tokenProvider: { "token" })
        let terminal = PayabliTTP(
            config: config,
            provider: provider,
            attestation: MockDeviceAttestationService(),
            retryPolicy: retryPolicy,
            session: StubURLProtocol.makeSession(),
            chargeKeys: keys,
            heldPayments: held
        )
        try await terminal.initialize()
        XCTAssertEqual(terminal.sessionState, .ready, "the fixture itself is broken if this fails")
        return (terminal, provider)
    }

    /// Three attempts with no wait between them.
    private static let noWait = RetryPolicy(
        maxAttempts: 3,
        baseDelay: 0,
        maxDelay: 0,
        multiplier: 1,
        maxJitter: 0,
        jitter: .none
    )

    /// Two attempts, `delay` seconds apart.
    private static func twoAttempts(apart delay: TimeInterval) -> RetryPolicy {
        RetryPolicy(maxAttempts: 2, baseDelay: delay, maxDelay: delay, multiplier: 1, maxJitter: 0, jitter: .none)
    }

    private static func failure(_ body: @MainActor () async throws -> Void) async -> TapToPayError? {
        do {
            try await body()
            XCTFail("expected a failure")
        } catch let failure as TapToPayError {
            return failure
        } catch {
            XCTFail("expected a TapToPayError, got \(error)")
        }
        return nil
    }
}
