import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// An unknown outcome carries the transaction the answer named, so a host can read it back.
@MainActor
final class PayInUnknownOutcomeTransactionTests: XCTestCase {
    func testAnUnknownOutcomeCarriesTheTransactionTheAnswerNamed() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"code":"E9999","reason":"Error","data":{"paymentTransId":"101-abc"}}"#.utf8),
            status: 500
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-1")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard case let .submissionInterrupted(type, _, paymentTransId) = failure as? PayabliPayInError else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(type, .serverError)
        XCTAssertEqual(paymentTransId, "101-abc")
    }

    func testAnUnknownOutcomeKeepsTheTransactionWhenAnotherFieldIsMalformed() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"code":"E9999","reason":"Error","data":{"paymentTransId":"101-abc","transStatus":"x"}}"#.utf8),
            status: 500
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-4")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard case let .submissionInterrupted(_, _, paymentTransId) = failure as? PayabliPayInError else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(paymentTransId, "101-abc")
    }

    func testAnUnknownOutcomeKeepsTheTransactionWhenTheAnswerCarriesNoCode() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"isSuccess":false,"reason":"Error","data":{"paymentTransId":"101-abc"}}"#.utf8),
            status: 500
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-5")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard case let .submissionInterrupted(_, _, paymentTransId) = failure as? PayabliPayInError else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(paymentTransId, "101-abc")
    }

    func testAnUnknownOutcomeWithNoAnswerCarriesNoTransaction() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(type: .networkError, reason: "offline")
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-2")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard case let .submissionInterrupted(_, _, paymentTransId) = failure as? PayabliPayInError else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertNil(paymentTransId)
    }

    func testAnUnknownOutcomeWhoseAnswerNamedNoTransactionCarriesNone() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"code":"E9999","reason":"Error","data":{"paymentTransId":"  "}}"#.utf8),
            status: 500
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-3")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request(idempotencyKey: nil))
        })

        guard case let .submissionInterrupted(_, _, paymentTransId) = failure as? PayabliPayInError else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertNil(paymentTransId)
    }
}
