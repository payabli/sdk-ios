@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// Which key a flow sends after another flow in this process left an attempt's outcome unknown.
///
/// Flows for the same entry point and environment share their held keys, so a rebuilt flow resends what its
/// predecessor held. Flows for another entry point or environment share nothing.
@MainActor
final class PayInKeyStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    private let transport = ScriptedTransport()
    private let clock = TestClock()
    private lazy var flow = makeFlow(prefix: "k")

    func testADeclaredRetryOnARebuiltFlowSendsTheHeldKey() async throws {
        transport.script = [.lost, .approved]
        let restarted = makeFlow(prefix: "n")

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await restarted.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1"])
    }

    func testAFlowForAnotherEntryPointHoldsNoneOfThisOnesKeys() async throws {
        transport.script = [.lost, .approved, .approved]
        let other = makeFlow(prefix: "n", entryPoint: "other")

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await other.capture(request(.retry))
        _ = try await other.capture(request(.newPayment, reference: "p2"))

        XCTAssertEqual(transport.sentKeys, ["k1", "n1", "n2"])
    }

    func testAFlowForAnotherEnvironmentHoldsNoneOfThisOnesKeys() async throws {
        transport.script = [.lost, .approved, .approved]
        let other = makeFlow(prefix: "n", environment: .production)

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        _ = try await other.capture(request(.retry))
        _ = try await other.capture(request(.newPayment))

        XCTAssertEqual(transport.sentKeys, ["k1", "n1", "n2"])
    }

    func testAKeyHeldByAnEarlierFlowStillAgesOut() async throws {
        transport.script = [.lost, .approved]
        let restarted = makeFlow(prefix: "n")

        _ = await failure { try await self.flow.capture(self.request(.newPayment)) }
        clock.advance(by: payabliIdempotencyKeyMaxAge)
        _ = try await restarted.capture(request(.retry))

        XCTAssertEqual(transport.sentKeys, ["k1", "n1"])
    }

    func testAFullEntryPointLeavesAnotherRoomToHold() async throws {
        let capacity = HeldIdempotencyKeys.capacity
        let other = makeFlow(prefix: "n", entryPoint: "other")
        transport.script = Array(repeating: .lost, count: capacity + 1) + [.approved]

        for index in 0 ..< capacity {
            _ = await failure { try await self.flow.voidTransaction("t-\(index)") }
        }
        _ = await failure { try await other.voidTransaction("t-0") }
        _ = try await other.voidTransaction("t-0")

        XCTAssertEqual(transport.sentKeys.suffix(2), ["n1", "n1"])
    }

    // MARK: - Recorded as it is made

    func testANewPaymentFromAnotherFlowWhileTheFirstIsSendingIsRefusedAndARetrySendsTheFirstKey() async throws {
        let held = HeldOpenTransport()
        let first = makeFlow(prefix: "k", transport: held)
        let second = makeFlow(prefix: "n", transport: held)

        let sending = Task { try await first.capture(self.request(.newPayment)) }
        await held.firstSendArrived()
        let refused = await failure { try await second.capture(self.request(.newPayment)) }
        _ = try await second.capture(request(.retry))
        held.release()
        _ = try await sending.value

        XCTAssertEqual((refused as? any PayabliError)?.type, .paymentReferenceOpen)
        XCTAssertEqual(held.sentKeys, ["k1", "k1"])
    }

    func testAKeyWhoseSendIsUnderWayOutlivesItsWindow() throws {
        let store = PayInKeyStore()
        let start = ContinuousClock.now
        _ = try reserve(in: store, claimsHeld: false, at: start, mint: "k1")

        let retried = try reserve(in: store, claimsHeld: true, at: start.advanced(by: payabliIdempotencyKeyMaxAge))

        XCTAssertEqual(retried.key, "k1")
    }

    func testAKeyNoSendCarriedOutIsDroppedWhenItsLastSendEnds() throws {
        let store = PayInKeyStore()
        let start = ContinuousClock.now
        let first = try reserve(in: store, claimsHeld: false, at: start, mint: "k1")
        let retry = try reserve(in: store, claimsHeld: true, at: start)

        store.settle(entry: "entry", environment: .sandbox, first, outcome: .notAnswered)
        XCTAssertThrowsError(try reserve(in: store, claimsHeld: false, at: start), "a send of it is under way") {
            XCTAssertEqual(($0 as? any PayabliError)?.type, .paymentReferenceOpen)
        }
        store.settle(entry: "entry", environment: .sandbox, retry, outcome: .notAnswered)
        let next = try reserve(in: store, claimsHeld: false, at: start, mint: "k2")

        XCTAssertEqual(next.key, "k2")
    }

    func testAnAnswerForgetsTheKeyThoughAnotherSendOfItIsUnderWay() throws {
        let store = PayInKeyStore()
        let start = ContinuousClock.now
        let first = try reserve(in: store, claimsHeld: false, at: start, mint: "k1")
        let retry = try reserve(in: store, claimsHeld: true, at: start)

        store.settle(entry: "entry", environment: .sandbox, first, outcome: .answered)
        store.settle(entry: "entry", environment: .sandbox, retry, outcome: .unknown)
        let next = try reserve(in: store, claimsHeld: false, at: start, mint: "k2")

        XCTAssertEqual(next.key, "k2")
    }

    // MARK: - Support

    private func makeFlow(
        prefix: String,
        entryPoint: String = "entry",
        environment: PayabliEnvironment = .sandbox,
        transport: (any PayabliTransport)? = nil
    ) -> PayabliPayIn {
        let flow = PayabliPayIn(entryPoint: entryPoint, environment: environment, transport: transport ?? self.transport)
        let minted = Counter()
        flow.newIdempotencyKey = { "\(prefix)\(minted.next())" }
        let clock = clock
        flow.now = { clock.now }
        return flow
    }

    private func request(_ attempt: PayabliAttempt, reference: String = "p1") -> PayabliPayInRequest {
        PayabliPayInRequest(
            paymentMethod: .stored(PayabliPayInPaymentMethod.Stored(method: .card, storedMethodId: "stored-1")),
            options: PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34),
                paymentReference: reference,
                attempt: attempt
            )
        )
    }

    private func failure(_ block: () async throws -> PayabliPayInResult) async -> any Error {
        await PayInFixture.failure(from: { _ = try await block() })
    }

    private func reserve(
        in store: PayInKeyStore,
        claimsHeld: Bool,
        at now: ContinuousClock.Instant,
        mint key: String = "minted"
    ) throws -> HeldIdempotencyKeys.Reservation {
        try store.reserve(
            entry: "entry", environment: .sandbox, scope: .capture(reference: "p1"),
            claimsHeld: claimsHeld, payment: nil, now: now, mint: { key }
        )
    }
}

/// Answers every send approved, and holds the first open until ``release()``.
private final class HeldOpenTransport: PayabliTransport, @unchecked Sendable {
    private static let approved = Data("""
    {"code":"A0000","reason":"Approved","responseData":{"authCode":"1","referenceId":"trans-1"}}
    """.utf8)

    private let lock = NSLock()
    private var keys: [String] = []
    private let arrivals = AsyncStream<Void>.makeStream()
    private let releases = AsyncStream<Void>.makeStream()

    var sentKeys: [String] {
        lock.withLock { keys }
    }

    /// Returns once the first send is under way.
    func firstSendArrived() async {
        for await _ in arrivals.stream {
            return
        }
    }

    /// Lets the first send be answered.
    func release() {
        releases.continuation.yield()
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        let isFirst = lock.withLock {
            keys.append(request.headers["idempotencyKey"] ?? "")
            return keys.count == 1
        }
        PayabliSendMark.current?.set()
        if isFirst {
            arrivals.continuation.yield()
            for await _ in releases.stream {
                break
            }
        }
        return PayabliResponse(statusCode: 200, headers: [:], body: Self.approved)
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
