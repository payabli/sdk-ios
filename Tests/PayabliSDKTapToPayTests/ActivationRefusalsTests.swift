import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// An activation refusal reaches a host under the catalog entry for what the service said, and a refusal it
/// does not recognise says nothing a host would act on wrongly.
final class ActivationRefusalsTests: XCTestCase {
    func testEveryRefusalTheServiceWordsReachesItsCatalogEntry() {
        let cases: [(Int?, String, PayabliErrorType)] = [
            (400, "Invalid activation code.", .activationCodeIncorrect),
            (400, "Activation code has expired. Request a new challenge.", .activationCodeExpired),
            (400, "Too many failed activation attempts. Request a new challenge.", .activationAttemptsExhausted),
            (400, "No active challenge for this device.", .activationCodeNotIssued),
            (400, "Stored activation code is invalid.", .activationCodeNotIssued),
            (400, "Device is not pending activation.", .deviceNotPending),
            (400, "Assertion verification failed: signature mismatch", .deviceSetupRequired),
            (400, "activationCode is required in the request body.", .sdkInternalError),
            (400, "X-Assertion-Timestamp header is required.", .sdkInternalError),
            (403, "Entry point is not available for this request.", .entryPointRefused),
            (404, "Device not found.", .deviceSetupRequired),
            (404, "Paypoint 'acme' was not found.", .entryPointRefused),
            (500, "Internal error", .serverError),
            (503, "", .serverError)
        ]
        for (code, reason, expected) in cases {
            XCTAssertEqual(
                ActivationRefusals.catalogType(resultCode: code, reason: reason),
                expected,
                "\(code.map(String.init) ?? "nil") \(reason)"
            )
        }
    }

    func testARefusalItDoesNotRecogniseIsUnknown() {
        let cases: [(Int?, String)] = [
            (400, "invalid activation code."),
            (400, "Invalid activation code"),
            (403, "Forbidden"),
            (404, "Not found"),
            (409, "Invalid activation code."),
            (nil, "Invalid activation code.")
        ]
        for (code, reason) in cases {
            XCTAssertEqual(
                ActivationRefusals.catalogType(resultCode: code, reason: reason),
                .unknown,
                "\(code.map(String.init) ?? "nil") \(reason)"
            )
        }
    }

    func testTheServicesWordsReachTheDetailAndTheReasonIsTheCatalogText() {
        let refusal = ActivationRefusals.hostError(resultCode: 400, reason: "Invalid activation code.")
        XCTAssertEqual(refusal.reason, PayabliErrorType.activationCodeIncorrect.message)
        XCTAssertEqual(refusal.detail, "Invalid activation code.")
        XCTAssertEqual(refusal.capture, .notCharged)
        XCTAssertNil(ActivationRefusals.hostError(resultCode: 503, reason: "").detail)
    }
}
