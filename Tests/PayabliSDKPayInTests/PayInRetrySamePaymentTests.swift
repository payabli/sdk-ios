@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A held key goes out only with the payment it was made for: a declared retry describing another payment is
/// refused before anything is sent, and the key stays for the right retry.
@MainActor
final class PayInRetrySamePaymentTests: XCTestCase {
    private let transport = ScriptedTransport()
    private let clock = TestClock()

    func testARetryForAnotherAmountIsRefusedUnsentAndTheKeyStays() async throws {
        let flow = makeFlow()
        transport.script = [.lost, .approved]

        _ = await failure { try await flow.capture(self.payment(.newPayment)) }
        let refused = await failure { try await flow.capture(self.payment(.retry, total: 20)) }
        _ = try await flow.capture(payment(.retry))

        XCTAssertEqual((refused as? any PayabliError)?.type, .retryNotSamePayment)
        XCTAssertEqual((refused as? any PayabliError)?.category, .invalidRequest)
        XCTAssertEqual(transport.sentKeys, ["k1", "k1"])
    }

    func testEachComparedFieldThatDiffersRefusesTheRetry() async {
        let variants: [(String, PayabliPayInRequest)] = [
            ("total", payment(.retry, total: 10.01, orderId: "order-1")),
            ("service fee", payment(.retry, fee: 0.5, orderId: "order-1")),
            ("surcharge", payment(.retry, surcharge: 0.5, orderId: "order-1")),
            ("currency", payment(.retry, currency: "CAD", orderId: "order-1")),
            ("method kind", payment(.retry, method: .bankAccount, orderId: "order-1")),
            ("order", payment(.retry, orderId: "order-2"))
        ]
        for (field, retry) in variants {
            let flow = makeFlow()
            transport.script = [.lost]
            _ = await failure { try await flow.capture(self.payment(.newPayment, orderId: "order-1")) }

            let refused = await failure { try await flow.capture(retry) }

            XCTAssertEqual((refused as? any PayabliError)?.type, .retryNotSamePayment, "a different \(field) was sent")
        }
        XCTAssertEqual(transport.sentKeys, Array(repeating: "k1", count: variants.count))
    }

    func testAmountsAreComparedAsTheRequestSendsThem() async throws {
        let flow = makeFlow()
        transport.script = [.lost, .approved]

        _ = await failure { try await flow.capture(self.payment(.newPayment, total: 1.005)) }
        let refused = await failure { try await flow.capture(self.payment(.retry, total: 1)) }
        _ = try await flow.capture(payment(.retry, total: 1.01))

        XCTAssertEqual((refused as? any PayabliError)?.type, .retryNotSamePayment, "1.005 is sent as 1.01")
        XCTAssertEqual(transport.sentKeys, ["k1", "k1"])
    }

    func testASurchargeIsComparedWithNoneCountingAsZero() async throws {
        for retry in [payment(.retry, surcharge: 2), payment(.retry)] {
            let flow = makeFlow()
            transport.script = [.lost]
            _ = await failure { try await flow.capture(self.payment(.newPayment, surcharge: 1)) }

            let refused = await failure { try await flow.capture(retry) }

            XCTAssertEqual((refused as? any PayabliError)?.type, .retryNotSamePayment)
        }
        let flow = makeFlow()
        transport.script = [.lost, .approved]
        _ = await failure { try await flow.capture(self.payment(.newPayment)) }
        _ = try await flow.capture(payment(.retry, surcharge: 0))

        XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k1", "k1"])
    }

    func testAKeyHeldAgainAfterItsRecordExpiredKeepsTheFirstPayment() throws {
        var keys = HeldIdempotencyKeys()
        let start = ContinuousClock.now
        let maxAge = payabliIdempotencyKeyMaxAge
        let first = try keys.reserve(
            scope: .capture(reference: "p1"), claimsHeld: false,
            payment: HeldPaymentDescription(payment(.newPayment)), now: start, mint: { "k1" }
        )
        keys.settle(first, outcome: .unknown, now: start)
        let resent = try keys.reserve(
            scope: .capture(reference: "p1"), claimsHeld: true,
            payment: HeldPaymentDescription(payment(.retry, orderId: "order-1")),
            now: start.advanced(by: maxAge - .seconds(1)), mint: { "k-other" }
        )
        keys.settle(resent, outcome: .unknown, now: start.advanced(by: maxAge))

        let retried = try keys.reserve(
            scope: .capture(reference: "p1"), claimsHeld: true,
            payment: HeldPaymentDescription(payment(.retry, orderId: "order-2")),
            now: start.advanced(by: maxAge), mint: { "k-other" }
        )

        XCTAssertEqual(retried.key, "k1", "the first attempt set no order, so the order is not compared")
    }

    func testARetryDescribingTheSamePaymentInOtherWordsTakesTheKey() async throws {
        let flow = makeFlow()
        transport.script = [.lost, .approved]

        _ = await failure { try await flow.authorize(self.payment(.newPayment, currency: "USD")) }
        _ = try await flow.authorize(
            payment(.retry, total: 10.001, fee: 0, currency: " usd", method: .cloudDevice, orderId: "o")
        )

        XCTAssertEqual(transport.sentKeys, ["k1", "k1"])
    }

    func testANewPaymentIsNeverCompared() async throws {
        let flow = makeFlow()
        transport.script = [.lost, .approved]

        _ = await failure { try await flow.capture(self.payment(.newPayment)) }
        _ = try await flow.capture(payment(.newPayment, total: 20, reference: "p2"))

        XCTAssertEqual(transport.sentKeys, ["k1", "k2"])
    }

    func testEachReferenceComparesAgainstItsOwnPayment() async throws {
        let flow = makeFlow()
        transport.script = [.lost, .lost, .approved]

        _ = await failure { try await flow.capture(self.payment(.newPayment)) }
        _ = await failure { try await flow.capture(self.payment(.newPayment, total: 20, reference: "p2")) }
        let refused = await failure { try await flow.capture(self.payment(.retry, total: 20)) }
        _ = try await flow.capture(payment(.retry, total: 20, reference: "p2"))

        XCTAssertEqual((refused as? any PayabliError)?.type, .retryNotSamePayment)
        XCTAssertEqual(transport.sentKeys, ["k1", "k2", "k2"])
    }

    // MARK: -

    private enum Method {
        case storedCard
        case cloudDevice
        case bankAccount
    }

    private func makeFlow() -> PayabliPayIn {
        let flow = PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport)
        let minted = Counter()
        flow.newIdempotencyKey = { "k\(minted.next())" }
        let clock = clock
        flow.now = { clock.now }
        return flow
    }

    private func payment(
        _ attempt: PayabliAttempt,
        total: Double = 10,
        fee: Double? = nil,
        surcharge: Double? = nil,
        currency: String? = nil,
        method: Method = .storedCard,
        orderId: String? = nil,
        reference: String = "p1"
    ) -> PayabliPayInRequest {
        PayabliPayInRequest(
            paymentMethod: paymentMethod(method),
            options: PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(
                    totalAmount: total,
                    serviceFee: fee,
                    surchargeFee: surcharge,
                    currency: currency
                ),
                orderId: orderId,
                paymentReference: reference,
                attempt: attempt
            )
        )
    }

    private func paymentMethod(_ method: Method) -> PayabliPayInPaymentMethod {
        switch method {
        case .storedCard:
            .stored(PayabliPayInPaymentMethod.Stored(method: .card, storedMethodId: "stored-1"))
        case .cloudDevice:
            .cloudDevice(PayabliPayInPaymentMethod.CloudDevice(device: "device-1"))
        case .bankAccount:
            .stored(PayabliPayInPaymentMethod.Stored(method: .bankAccount, storedMethodId: "stored-2"))
        }
    }

    private func failure(_ block: () async throws -> PayabliPayInResult) async -> any Error {
        await PayInFixture.failure(from: { _ = try await block() })
    }
}
