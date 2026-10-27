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

    // MARK: - Support

    private func makeFlow(
        prefix: String,
        entryPoint: String = "entry",
        environment: PayabliEnvironment = .sandbox
    ) -> PayabliPayIn {
        let flow = PayabliPayIn(entryPoint: entryPoint, environment: environment, transport: transport)
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
}
