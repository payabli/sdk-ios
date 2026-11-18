import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// An Objective-C caller passes an enum as a plain integer, so a charge can carry a number that names no case. The
/// charge refuses it with a validation error before anything is sent, rather than reaching a switch that traps.
@available(iOS 16.7, *)
@MainActor
final class PayabliTTPObjCChargeRefusalTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = { request in
            XCTFail("nothing is sent: \(request.url?.path ?? "")")
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testACurrencyNamingNoCaseIsRefusedBeforeTheCharge() async throws {
        let request = PayabliTTPChargeRequestObjC(paymentDetails: PayabliTTPPaymentDetailsObjC(
            amount: 1,
            serviceFee: 0,
            currency: unsafeBitCast(99, to: PayabliCurrency.self),
            paymentDescription: nil
        ))

        let failure = try await refusal(of: request)

        XCTAssertEqual(failure.code, PayabliErrorType.validation.number)
        XCTAssertTrue(failure.localizedDescription.contains("paymentDetails.currency"), failure.localizedDescription)
        XCTAssertEqual(failure.userInfo["capture"] as? Int, PayabliTTPCapture.notCharged.rawValue)
    }

    func testAnAttemptNamingNoCaseIsRefusedBeforeTheCharge() async throws {
        let request = PayabliTTPChargeRequestObjC(paymentDetails: PayabliTTPPaymentDetailsObjC(
            amount: 1, serviceFee: 0, currency: .usd, paymentDescription: nil
        ))
        request.attempt = unsafeBitCast(-1, to: PayabliAttempt.self)

        let failure = try await refusal(of: request)

        XCTAssertEqual(failure.code, PayabliErrorType.validation.number)
        XCTAssertTrue(failure.localizedDescription.contains("attempt"), failure.localizedDescription)
    }

    // MARK: -

    private func refusal(of request: PayabliTTPChargeRequestObjC) async throws -> NSError {
        let ttp = try PayabliTTP(
            config: PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
            provider: MockTapToPayProvider(),
            attestation: MockDeviceAttestationService(),
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        let (result, error) = await withCheckedContinuation { continuation in
            ttp.charge(request) { result, error in continuation.resume(returning: (result, error)) }
        }
        XCTAssertNil(result)
        return try XCTUnwrap(error)
    }
}
