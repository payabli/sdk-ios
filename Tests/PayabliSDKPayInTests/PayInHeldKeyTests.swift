@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// Which key a repeat sends after an attempt whose outcome nobody knows.
///
/// A capture or an authorization takes the held key only when the host declares a retry. A capture of an
/// authorization and a reversal resend their transaction's held key on their own.
@MainActor
final class PayInHeldKeyTests: XCTestCase {
    private let transport = ScriptedTransport()
    private let clock = TestClock()
    private lazy var flow = makeFlow(prefix: "k")

    // MARK: - A capture or an authorization

    func testANewPaymentUnderAnotherReferenceSendsANewKey() async throws {
        transport.script = [.lost, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await flow.capture(request(.newPayment, reference: "p2"))

        XCTAssertEqual(transport.sentKeys, ["k1", "k2"])
    }

    func testANewPaymentOnAReferenceWhoseKeyIsHeldIsRefusedUnsent() async throws {
        transport.script = [.lost, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        let refused = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual((refused as? any PayabliError)?.type, .paymentReferenceOpen)
        XCTAssertEqual((refused as? any PayabliError)?.category, .invalidRequest)
        XCTAssertEqual(transport.sentKeys, ["k1", "k1"])
    }

    func testAReferenceIsFreeAgainOnceItsPaymentIsAnswered() async throws {
        transport.script = [.lost, .approved, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await flow.capture(request(.retry))
        _ = try await flow.capture(request(.newPayment))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"])
    }

    func testABlankReferenceIsRefusedUnsent() async {
        let refused = await failure { try await self.flow.capture(self.request(.newPayment, reference: " ")) }

        XCTAssertEqual(refused as? PayabliPayInError, .invalidInput("The payment reference cannot be blank."))
        XCTAssertEqual(transport.sentKeys, [])
    }

    func testAnUnnamedPaymentIsGivenAReferenceThatAnUnknownOutcomeReturns() async throws {
        flow.newPaymentReference = { "minted-1" }
        transport.script = [.lost, .approved]

        let interrupted = await failure { try await self.flow.capture(self.request(.newPayment, reference: nil)) }
        _ = try await flow.capture(request(.retry, reference: "minted-1"))

        XCTAssertEqual(Self.reference(in: interrupted), "minted-1")
        XCTAssertEqual(transport.sentKeys, ["k1", "k1"])
    }

    func testAReferenceIsComparedAndReturnedTrimmed() async throws {
        transport.script = [.lost, .approved]

        let interrupted = await failure { try await self.flow.capture(self.request(.newPayment, reference: " p1 ")) }
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(Self.reference(in: interrupted), "p1")
        XCTAssertEqual(transport.sentKeys, ["k1", "k1"])
    }

    func testADeclaredRetrySendsTheKeyOfTheAttemptNobodyKnows() async throws {
        transport.script = [.lost, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1"])
    }

    func testAHeldKeyIsStillSentInsideTheWindow() async throws {
        transport.script = [.lost, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge - .seconds(1))
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1"])
    }

    func testAHeldKeyIsNotSentOnceTheServiceWouldHaveForgottenIt() async throws {
        transport.script = [.lost, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge)
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k2"])
    }

    func testAFailureBeforeAnythingIsSentKeepsTheHeldKey() async throws {
        transport.script = [.lost, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = await failure { try await self.flow.capture(self.request(.retry, totalAmount: 0)) }
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1"])
    }

    func testTheWindowIsTheServicesTwoMinutesPlusFourWholeCalls() {
        XCTAssertEqual(payabliIdempotencyKeyMaxAge, .seconds(240))
    }

    /// The service may first have seen the key on the resend, so the key's age counts from there.
    func testAResendThatMayHaveArrivedRestartsTheKeysAge() async throws {
        transport.script = [.lost, .lost, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge - .seconds(1))
        _ = await failure { try await self.flow.capture(self.request(.retry)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge - .seconds(1))
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k1"])
    }

    func testAResendThatNeverLeftDoesNotRestartTheKeysAge() async throws {
        transport.script = [.lost, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge - .seconds(1))
        _ = await failure { try await self.flow.capture(self.request(.retry, totalAmount: 0)) }
        clock.advance(by: .seconds(1))
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k2"])
    }

    func testACancellationBeforeTheHandOffDoesNotRestartTheKeysAge() async throws {
        transport.script = [.lost, .cancelled(afterHandOff: false), .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge - .seconds(1))
        _ = await failure { try await self.flow.capture(self.request(.retry)) }
        clock.advance(by: .seconds(1))
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"])
    }

    func testACancellationAfterTheHandOffRestartsTheKeysAge() async throws {
        transport.script = [.lost, .cancelled(afterHandOff: true), .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge - .seconds(1))
        _ = await failure { try await self.flow.capture(self.request(.retry)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge - .seconds(1))
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k1"])
    }

    func testAFailureBeforeTheHandOffHoldsNoKey() async throws {
        transport.script = [.lostBeforeHandOff, .cancelled(afterHandOff: false), .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k2", "k3"])
    }

    func testADeclineForgetsTheHeldKey() async throws {
        transport.script = [.lost, .declined, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = await failure { try await self.flow.capture(self.request(.retry)) }
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"])
    }

    func testASuccessForgetsTheHeldKey() async throws {
        transport.script = [.lost, .approved, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await flow.capture(request(.retry))
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"])
    }

    func testAnotherReferenceNeitherTakesNorClearsTheHeldKey() async throws {
        transport.script = [.lost, .approved, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await flow.capture(request(.newPayment, reference: "p2"))
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k2", "k1"])
    }

    func testEachReferenceRetriesUnderItsOwnKey() async throws {
        transport.script = [.lost, .lost, .approved, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = await failure { try await self.flow.capture(self.request(.newPayment, reference: "p2")) }
        _ = try await flow.capture(request(.retry))
        _ = try await flow.capture(request(.retry, reference: "p2"))

        XCTAssertEqual(transport.sentKeys, ["k1", "k2", "k1", "k2"])
    }

    func testARefusedCredentialOnAResentKeyLeavesTheOutcomeOpenAndKeepsTheKey() async throws {
        transport.script = [.lost, .unauthorized, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge - .seconds(1))
        let refused = await failure { try await self.flow.capture(self.request(.retry)) }
        clock.advance(by: .seconds(1))
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(PayInFixture.interruption(refused)?.type, .tokenExpired)
        XCTAssertEqual(Self.reference(in: refused), "p1")
        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"], "the refused send restarted the key's age")
    }

    func testARefusedCredentialOnANewKeyIsATokenErrorAndHoldsNothing() async throws {
        transport.script = [.unauthorized, .approved]

        let refused = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual((refused as? any PayabliError)?.type, .tokenExpired)
        XCTAssertNil(PayInFixture.interruption(refused), "a new key's refused credential left the outcome open")
        XCTAssertEqual(transport.sentKeys, ["k1", "k2"])
    }

    func testANewKeyThatNeverLeftReportsThePlainFailure() async {
        transport.script = [.cancelled(afterHandOff: false), .lostBeforeHandOff]

        let cancelled = await failure { try await self.flow.capture(self.request(.newPayment)) }
        let lost = await failure { try await self.flow.capture(self.request(.newPayment, reference: "p2")) }

        XCTAssertTrue(cancelled is CancellationError, "\(cancelled)")
        XCTAssertEqual((lost as? PayabliGenericError)?.type, .networkError)
    }

    func testAResentKeyThatNeverLeftStillReportsAnOpenOutcome() async {
        transport.script = [.lost, .tokenFetchFailed, .cancelled(afterHandOff: false)]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        let noToken = await failure { try await self.flow.capture(self.request(.retry)) }
        let cancelled = await failure { try await self.flow.capture(self.request(.retry)) }

        XCTAssertEqual(PayInFixture.interruption(noToken)?.type, .tokenProviderFailed)
        XCTAssertEqual(Self.reference(in: noToken), "p1")
        XCTAssertNotNil(PayInFixture.interruption(cancelled), "\(cancelled)")
        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k1"])
    }

    func testAKeyThatAgesOutDuringAnUnknownSendIsHeldOnTheRestartedClock() async throws {
        transport.script = [.lost, .lost, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge - .seconds(1))
        let clock = clock
        transport.duringSend = { clock.advance(by: .seconds(2)) }
        _ = await failure { try await self.flow.capture(self.request(.retry)) }
        transport.duringSend = nil
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k1"])
    }

    func testAKeyThatAgesOutDuringARefusedSendStaysGone() async throws {
        transport.script = [.lost, .duplicate, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge - .seconds(1))
        let clock = clock
        transport.duringSend = { clock.advance(by: .seconds(2)) }
        _ = await failure { try await self.flow.capture(self.request(.retry)) }
        transport.duringSend = nil
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"])
    }

    func testAConflictIsReadFromTheStatusWhateverTheBodySays() async throws {
        let envelopes = [
            #"{"status":200,"message":"Duplicate payment"}"#,
            #"{"isSuccess":false,"responseCode":6000,"responseText":"Duplicate payment"}"#,
            #"{"status":401,"message":"Duplicate payment"}"#
        ]
        for envelope in envelopes {
            let flow = makeFlow(prefix: "k")
            transport.script = [.lost, .conflict(envelope), .approved]
            _ = await failure { try await flow.capture(self.request(.newPayment)) }

            let refused = await failure { try await flow.capture(self.request(.retry)) }
            _ = try await flow.capture(request(.retry))

            XCTAssertEqual(PayInFixture.interruption(refused)?.type, .conflict, envelope)
            XCTAssertEqual(transport.sentKeys.suffix(3), ["k1", "k1", "k2"], "the conflict kept the key: \(envelope)")
        }
    }

    func testATransactionsUnknownOutcomeCarriesNoReference() async {
        transport.script = [.lost]

        let interrupted = await failure { try await self.flow.voidTransaction("t-1") }

        XCTAssertNotNil(PayInFixture.interruption(interrupted))
        XCTAssertNil(Self.reference(in: interrupted))
    }

    func testARetryWithNothingHeldSendsANewKey() async throws {
        transport.script = [.approved]

        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1"])
    }

    func testACaptureAndAnAuthorizationHoldTheirOwnKeys() async throws {
        transport.script = [.lost, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await flow.authorize(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k2"])
    }

    func testAnAuthorizationRetrySendsItsHeldKey() async throws {
        transport.script = [.lost, .approved]

        _ = await failure { try await self.flow.authorize(self.request(.newPayment)) }
        _ = try await flow.authorize(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1"])
    }

    // MARK: - A refused repeat

    func testARefusedRetryIsRetryRefusedAndKeepsItsKey() async throws {
        transport.script = [.lost, .duplicate, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        let refused = await failure { try await self.flow.capture(self.request(.retry)) }
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(PayInFixture.interruption(refused)?.type, .retryRefused)
        XCTAssertEqual((refused as? any PayabliError)?.category, .outcomeUnknown)
        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k1"])
    }

    /// The refusal proves an earlier send arrived, and the service's memory of the key counts from that send.
    func testARefusedRetryRestartsNothingAndItsKeyStillAgesOut() async throws {
        transport.script = [.lost, .duplicate, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge - .seconds(1))
        _ = await failure { try await self.flow.capture(self.request(.retry)) }
        clock.advance(by: .seconds(1))
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"])
    }

    func testADuplicatePaymentOnAHeldKeyStaysAConflictAndForgetsTheKey() async throws {
        transport.script = [.lost, .duplicatePayment, .approved]

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        let refused = await failure { try await self.flow.capture(self.request(.retry)) }
        _ = try await flow.capture(request(.retry))

        XCTAssertEqual(PayInFixture.interruption(refused)?.type, .conflict)
        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"])
    }

    /// Whether a 409 refuses the key turns on whether its body is a JSON object, never on a field's name.
    func testOnlyAConflictWithoutAJSONObjectIsARefusedRetry() async {
        let bodies: [(String, PayabliErrorType)] = [
            (#"{"IsSuccess":false,"ResponseText":"Duplicate payment"}"#, .conflict),
            (#"{"isSuccess":"no"}"#, .conflict),
            ("Duplicated idempotencyKey", .retryRefused),
            (#""Duplicated idempotencyKey""#, .retryRefused),
            ("", .retryRefused)
        ]
        for (body, expected) in bodies {
            let flow = makeFlow(prefix: "k")
            transport.script = [.lost, .conflict(body)]
            _ = await failure { try await flow.capture(self.request(.newPayment)) }

            let refused = await failure { try await flow.capture(self.request(.retry)) }

            XCTAssertEqual(PayInFixture.interruption(refused)?.type, expected, "a 409 carrying \(body)")
        }
    }

    // MARK: - A transaction named by the call

    func testACaptureOfAnAuthorizationResendsItsHeldKey() async throws {
        transport.script = [.lost, .approved, .approved]

        _ = await failure { try await self.flow.captureAuthorizedTransaction(self.authorized("t-1")) }
        _ = try await flow.captureAuthorizedTransaction(authorized("t-1"))
        _ = try await flow.captureAuthorizedTransaction(authorized("t-2"))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"])
    }

    func testAVoidResendsItsHeldKeyUntilItIsAnswered() async throws {
        transport.script = [.lost, .approved, .approved]

        _ = await failure { try await self.flow.voidTransaction("t-1") }
        _ = try await flow.voidTransaction("t-1")
        _ = try await flow.voidTransaction("t-1")

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"])
    }

    func testARefusedRepeatOnATransactionIsRetryRefused() async {
        transport.script = [.lost, .duplicate]

        _ = await failure { try await self.flow.voidTransaction("t-1") }
        let refused = await failure { try await self.flow.voidTransaction("t-1") }

        XCTAssertEqual(PayInFixture.interruption(refused)?.type, .retryRefused)
    }

    func testADuplicatePaymentOnATransactionsHeldKeyStaysAConflictAndForgetsTheKey() async throws {
        transport.script = [.lost, .duplicatePayment, .approved]

        _ = await failure { try await self.flow.captureAuthorizedTransaction(self.authorized("t-1")) }
        let refused = await failure { try await self.flow.captureAuthorizedTransaction(self.authorized("t-1")) }
        _ = try await flow.captureAuthorizedTransaction(authorized("t-1"))

        XCTAssertEqual(PayInFixture.interruption(refused)?.type, .conflict)
        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"])
    }

    func testANewFlowHoldsNoKey() async throws {
        transport.script = [.lost, .approved, .approved]
        let restarted = makeFlow(prefix: "n")

        _ = await failure { try await self.flow.captureAuthorizedTransaction(self.authorized("t-1")) }
        _ = try await restarted.captureAuthorizedTransaction(authorized("t-1"))
        _ = try await restarted.voidTransaction("t-1")

        XCTAssertEqual(transport.sentKeys, ["k1", "n1", "n2"])
    }

    func testPastItsCapacityAnAttemptIsSentButNotHeld() async throws {
        let capacity = HeldIdempotencyKeys.capacity
        transport.script = Array(repeating: .lost, count: capacity + 1) + [.approved, .approved]

        for index in 0 ... capacity {
            _ = await failure { try await self.flow.voidTransaction("t-\(index)") }
        }
        _ = try await flow.voidTransaction("t-\(capacity)")
        _ = try await flow.voidTransaction("t-0")

        XCTAssertEqual(transport.sentKeys.suffix(2), ["k\(capacity + 2)", "k1"])
    }

    func testAKeyThatExpiresDuringASendGivesUpItsPlaceToTheNewOne() throws {
        var keys = HeldIdempotencyKeys()
        let start = ContinuousClock.now
        let maxAge = payabliIdempotencyKeyMaxAge
        for index in 0 ..< HeldIdempotencyKeys.capacity {
            let reservedAt = index == 0 ? start : start.advanced(by: .seconds(10))
            let held = try keys.reserve(
                scope: .void(transId: "t-\(index)"), claimsHeld: true, now: reservedAt, mint: { "k\(index)" }
            )
            keys.settle(held, outcome: .unknown, now: reservedAt)
        }

        let sent = try keys.reserve(
            scope: .void(transId: "t-new"), claimsHeld: true,
            now: start.advanced(by: maxAge - .seconds(1)), mint: { "k-new" }
        )
        let full = keys.settle(sent, outcome: .unknown, now: start.advanced(by: maxAge))
        let retried = try keys.reserve(
            scope: .void(transId: "t-new"), claimsHeld: true,
            now: start.advanced(by: maxAge), mint: { "k-other" }
        )

        XCTAssertFalse(full, "payin_retry_keys_full is not logged")
        XCTAssertEqual(retried.key, "k-new")
    }

    // MARK: - Support

    private func makeFlow(prefix: String) -> PayabliPayIn {
        let flow = PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport)
        let minted = Counter()
        flow.newIdempotencyKey = { "\(prefix)\(minted.next())" }
        let clock = clock
        flow.now = { clock.now }
        return flow
    }

    private func request(
        _ attempt: PayabliAttempt,
        reference: String? = "p1",
        totalAmount: Double = 12.34
    ) -> PayabliPayInRequest {
        PayabliPayInRequest(
            paymentMethod: .stored(PayabliPayInPaymentMethod.Stored(method: .card, storedMethodId: "stored-1")),
            options: PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: totalAmount),
                paymentReference: reference,
                attempt: attempt
            )
        )
    }

    private func authorized(_ transId: String) -> PayabliPayInAuthorizedRequest {
        PayabliPayInAuthorizedRequest(
            transId: transId,
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10)
        )
    }

    private static func reference(in failure: any Error) -> String? {
        guard case let .submissionInterrupted(_, _, _, reference) = failure as? PayabliPayInError else { return nil }
        return reference
    }

    private func failure(_ block: () async throws -> PayabliPayInResult) async -> any Error {
        await PayInFixture.failure(from: { _ = try await block() })
    }
}

/// A clock a test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now

    var now: ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    func advance(by duration: Duration) {
        lock.lock()
        instant = instant.advanced(by: duration)
        lock.unlock()
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

/// Answers each call with the next step of its script, and records the key each call sent.
///
/// Every step but a failure before the hand-off marks the send as one that may have left the device.
final class ScriptedTransport: PayabliTransport, @unchecked Sendable {
    enum Step {
        case approved
        case declined
        case duplicate
        case duplicatePayment
        case conflict(String)
        case lost
        case unauthorized
        case lostBeforeHandOff
        case tokenFetchFailed
        case cancelled(afterHandOff: Bool)
    }

    private static let approved = Data("""
    {"code":"A0000","reason":"Approved","responseData":{"authCode":"1","referenceId":"trans-1"}}
    """.utf8)
    private static let declined = Data("""
    {"code":"D0001","reason":"Declined","explanation":"Declined by the issuer."}
    """.utf8)

    private static let duplicatePayment = Data("""
    {"responseText":"Duplicate payment","isSuccess":false,
     "responseData":{"resultCode":3,"referenceId":"trans-0","resultText":"Approved"}}
    """.utf8)

    private let lock = NSLock()
    private var keys: [String] = []
    private var steps: [Step] = []
    private var inFlight: (() -> Void)?

    /// Runs while each call is in flight, after its key is recorded.
    var duringSend: (() -> Void)? {
        get { lock.withLock { inFlight } }
        set { lock.withLock { inFlight = newValue } }
    }

    var script: [Step] {
        get { lock.withLock { steps } }
        set { lock.withLock { steps = newValue } }
    }

    var sentKeys: [String] {
        lock.withLock { keys }
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        let step: Step = lock.withLock {
            keys.append(request.headers["idempotencyKey"] ?? "")
            return steps.isEmpty ? .lost : steps.removeFirst()
        }
        switch step {
        case .lostBeforeHandOff, .cancelled(afterHandOff: false), .tokenFetchFailed:
            break
        default:
            PayabliSendMark.current?.set()
        }
        duringSend?()
        switch step {
        case .approved:
            return PayabliResponse(statusCode: 200, headers: [:], body: Self.approved)
        case .declined:
            return PayabliResponse(statusCode: 200, headers: [:], body: Self.declined)
        case .duplicate:
            let refusal = "Duplicated idempotencyKey: \(request.headers["idempotencyKey"] ?? "")"
            return PayabliResponse(statusCode: 409, headers: [:], body: Data(refusal.utf8))
        case .duplicatePayment:
            return PayabliResponse(statusCode: 409, headers: [:], body: Self.duplicatePayment)
        case let .conflict(body):
            return PayabliResponse(statusCode: 409, headers: [:], body: Data(body.utf8))
        case .tokenFetchFailed:
            throw PayabliGenericError(type: .tokenProviderFailed, reason: "No token")
        case .lost, .lostBeforeHandOff:
            throw PayabliGenericError(type: .networkError, reason: "The response was lost.")
        case .cancelled:
            throw CancellationError()
        case .unauthorized:
            throw PayabliGenericError(type: .tokenExpired, reason: "Token expired")
        }
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        let response = try await perform(request)
        try mapPayabliHTTPError(response: response)
        return try decodePayabliV2Envelope(T.self, from: response)
    }
}
