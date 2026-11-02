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
        XCTAssertEqual(payabli?.message, "This device's secure storage is unavailable.")
        XCTAssertEqual(payabli?.reason, "r")
        XCTAssertEqual(payabli?.detail, "d")
    }

    func testABridgedCallerReadsTheCatalogNumberAsTheErrorCode() {
        let error = TapToPayError(type: .deviceSetupUnsupported, reason: "r", detail: nil) as NSError

        XCTAssertEqual(error.domain, TapToPayError.errorDomain)
        XCTAssertEqual(error.code, 3002)
        XCTAssertEqual(error.userInfo["PayabliErrorType"] as? String, "DEVICE_SETUP_UNSUPPORTED")
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

    func testAFailureThatIsNotAChargesOwnRefusalCarriesNone() {
        let error = TapToPayError(type: .validation, reason: "r", detail: nil)

        XCTAssertNil(error.refusal)
        XCTAssertNil((error as NSError).userInfo["refusal"])
        XCTAssertNil((error as NSError).userInfo["requiredFields"])
    }

    func testACustomerDataRefusalReachesABridgedCallerWithTheFieldsItNames() {
        let error: any Error = TapToPayError(
            type: .validation,
            reason: "r",
            detail: nil,
            refusal: .customerDataRefused(requiredFields: ["customerNumber", "billingEmail"])
        )

        let bridged = error.toPayabliNSError()

        XCTAssertEqual((error as? TapToPayError)?.refusal, .customerDataRefused(requiredFields: ["customerNumber", "billingEmail"]))
        XCTAssertEqual(bridged.code, 1016)
        XCTAssertEqual(bridged.userInfo["refusal"] as? String, "customerDataRefused")
        XCTAssertEqual(bridged.userInfo["requiredFields"] as? [String], ["customerNumber", "billingEmail"])
    }

    func testACustomerDataRefusalNamingNoFieldsStillReachesABridgedCaller() {
        let error = TapToPayError(
            type: .validation,
            reason: "r",
            detail: nil,
            refusal: .customerDataRefused(requiredFields: [])
        ) as NSError

        XCTAssertEqual(error.userInfo["refusal"] as? String, "customerDataRefused")
        XCTAssertEqual(error.userInfo["requiredFields"] as? [String], [])
    }
}
