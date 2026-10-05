import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

final class TapToPayErrorTests: XCTestCase {
    func testItIsOneOfTheSDKsErrorsAndCarriesItsCode() {
        let error: any Error = TapToPayError(type: .deviceKeyUnavailable, reason: "r", detail: "d")

        let payabli = error as? any PayabliError
        XCTAssertEqual(payabli?.type, .deviceKeyUnavailable)
        XCTAssertEqual(payabli?.code, 3001)
        XCTAssertEqual(payabli?.category, .retryLater)
        XCTAssertEqual(payabli?.message, "The device's key facility could not confirm this device's key.")
        XCTAssertEqual(payabli?.reason, "r")
        XCTAssertEqual(payabli?.detail, "d")
    }

    func testABridgedCallerReadsTheCatalogNumberAsTheErrorCode() {
        let error = TapToPayError(type: .attestationNotSupported, reason: "r", detail: nil) as NSError

        XCTAssertEqual(error.domain, TapToPayError.errorDomain)
        XCTAssertEqual(error.code, 3002)
        XCTAssertEqual(error.userInfo["PayabliErrorType"] as? String, "ATTESTATION_NOT_SUPPORTED")
    }

    func testAFailureOutsideAPaymentMovedNoMoney() {
        let error = TapToPayError(type: .deviceKeyUnavailable, reason: "r", detail: nil)

        XCTAssertEqual(error.capture, .notCharged)
        XCTAssertNil(error.paymentTransId)
        XCTAssertEqual((error as NSError).userInfo["capture"] as? Int, PayabliTTPCapture.notCharged.rawValue)
    }

    func testAPaymentsIdentifierReachesABridgedCaller() {
        let error = TapToPayError(type: .networkError, reason: "r", detail: nil, paymentTransId: "txn", capture: .unknown)

        XCTAssertEqual((error as NSError).userInfo["paymentTransId"] as? String, "txn")
        XCTAssertEqual((error as NSError).userInfo["capture"] as? Int, PayabliTTPCapture.unknown.rawValue)
    }

    /// The conversion every completion handler applies, which a plain cast does not exercise.
    func testTheCompletionHandlersConversionKeepsTheCatalogNumberAndThePayment() {
        let error: any Error = TapToPayError(
            type: .deviceKeyUnavailable,
            reason: "r",
            detail: nil,
            paymentTransId: "txn",
            capture: .unknown
        )

        let bridged = error.toPayabliNSError()

        XCTAssertEqual(bridged.domain, TapToPayError.errorDomain)
        XCTAssertEqual(bridged.code, 3001)
        XCTAssertEqual(bridged.userInfo["paymentTransId"] as? String, "txn")
        XCTAssertEqual(bridged.userInfo["capture"] as? Int, PayabliTTPCapture.unknown.rawValue)
    }
}
