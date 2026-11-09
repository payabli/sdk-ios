import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// An unknown outcome carries the transaction the answer named, so a host can read it back.
@MainActor
final class PayInUnknownOutcomeTransactionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    func testAnUnknownOutcomeCarriesTheTransactionTheAnswerNamed() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"code":"E9999","reason":"Error","data":{"paymentTransId":"101-abc"}}"#.utf8),
            status: 500
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-1")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request())
        })

        guard let unsettled = failure as? PayabliPayInError.Unsettled else {
            return XCTFail("expected Unsettled, got \(failure)")
        }
        XCTAssertEqual(unsettled.type, .serverError)
        XCTAssertEqual(unsettled.paymentTransId, "101-abc")
    }

    func testAnUnknownOutcomeKeepsTheTransactionWhenAnotherFieldIsMalformed() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"code":"E9999","reason":"Error","data":{"paymentTransId":"101-abc","transStatus":"x"}}"#.utf8),
            status: 500
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-4")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request())
        })

        guard let unsettled = failure as? PayabliPayInError.Unsettled else {
            return XCTFail("expected Unsettled, got \(failure)")
        }
        XCTAssertEqual(unsettled.paymentTransId, "101-abc")
    }

    func testAnUnknownOutcomeKeepsTheTransactionWhenTheAnswerCarriesNoCode() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"isSuccess":false,"reason":"Error","data":{"paymentTransId":"101-abc"}}"#.utf8),
            status: 500
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-5")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request())
        })

        guard let unsettled = failure as? PayabliPayInError.Unsettled else {
            return XCTFail("expected Unsettled, got \(failure)")
        }
        XCTAssertEqual(unsettled.paymentTransId, "101-abc")
    }

    func testAnAnswerThatCannotBeReadKeepsTheTransactionItNames() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"code":"A0000","data":{"paymentTransId":"101-abc","transStatus":"x"}}"#.utf8),
            status: 200
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-6")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request())
        })

        guard let unsettled = failure as? PayabliPayInError.Unsettled else {
            return XCTFail("expected Unsettled, got \(failure)")
        }
        XCTAssertEqual(unsettled.type, .decodingError)
        XCTAssertEqual(unsettled.paymentTransId, "101-abc")
    }

    func testAServerErrorNamingOnlyATransactionKeepsIt() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"data":{"paymentTransId":" 101-abc "}}"#.utf8),
            status: 500
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-7")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request())
        })

        guard let unsettled = failure as? PayabliPayInError.Unsettled else {
            return XCTFail("expected Unsettled, got \(failure)")
        }
        XCTAssertEqual(unsettled.type, .serverError)
        XCTAssertEqual(unsettled.paymentTransId, "101-abc")
    }

    func testAnUnknownOutcomeWithNoAnswerCarriesNoTransaction() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(type: .networkError, reason: "offline")
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-2")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request())
        })

        guard let unsettled = failure as? PayabliPayInError.Unsettled else {
            return XCTFail("expected Unsettled, got \(failure)")
        }
        XCTAssertNil(unsettled.paymentTransId)
    }

    func testAnUnknownOutcomeWhoseAnswerNamedNoTransactionCarriesNone() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"code":"E9999","reason":"Error","data":{"paymentTransId":"  "}}"#.utf8),
            status: 500
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-3")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request())
        })

        guard let unsettled = failure as? PayabliPayInError.Unsettled else {
            return XCTFail("expected Unsettled, got \(failure)")
        }
        XCTAssertNil(unsettled.paymentTransId)
    }
}
