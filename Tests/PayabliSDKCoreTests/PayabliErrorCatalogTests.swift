import PayabliSDKCore
import XCTest

/// The published catalog: every code's number, category and message, exactly as both SDKs declare them.
final class PayabliErrorCatalogTests: XCTestCase {
    private typealias Row = (PayabliErrorCode, Int, PayabliErrorCategory, String)

    private let table: [Row] = [
        (.missingToken, 1001, .credential, "No access token is available."),
        (.tokenExpired, 1002, .credential, "The access token expired or was rejected."),
        (.tokenMalformed, 1003, .credential, "The access token could not be read."),
        (.tokenProviderFailed, 1004, .credential, "The token provider did not return a usable token."),
        (.invalidSignature, 1005, .credential, "The request signature was rejected."),
        (.permissionDenied, 1006, .configuration, "The credentials are not permitted to make this request."),
        (.sessionBurned, 1007, .credential, "The session can no longer be used."),
        (.paymentDeclined, 1008, .declined, "The payment was declined."),
        (.serverError, 1009, .outcomeUnknown, "The service could not process the request."),
        (.rateLimited, 1010, .retryLater, "Too many requests. Try again later."),
        (.conflict, 1011, .declined, "The request conflicts with the state the service holds."),
        (.invalidConfiguration, 1012, .configuration, "The SDK is not configured correctly."),
        (.networkError, 1013, .outcomeUnknown, "The service could not be reached."),
        (.decodingError, 1014, .outcomeUnknown, "The response could not be read."),
        (.userCancelled, 1015, .outcomeUnknown, "The person cancelled."),
        (.validation, 1016, .invalidRequest, "The request was refused as invalid."),
        (.unknown, 1017, .outcomeUnknown, "An unexpected error occurred."),
        (.deviceKeyUnavailable, 3001, .retryLater, "The device's key facility could not confirm this device's key."),
        (.attestationNotSupported, 3002, .device, "This device does not support app attestation.")
    ]

    func testEveryCodeCarriesItsPublishedNumberCategoryAndMessage() {
        for (code, number, category, message) in table {
            XCTAssertEqual(code.number, number, "\(code)")
            XCTAssertEqual(code.category, category, "\(code)")
            XCTAssertEqual(code.message, message, "\(code)")
        }
    }

    func testTheTableCoversEveryCode() {
        XCTAssertEqual(Set(table.map(\.0)), Set(PayabliErrorCode.allCases))
    }

    func testNoTwoCodesShareANumber() {
        let numbers = PayabliErrorCode.allCases.map(\.number)
        XCTAssertEqual(Set(numbers).count, numbers.count)
    }

    func testTheNewCodesKeepTheirWireNames() {
        XCTAssertEqual(PayabliErrorCode.deviceKeyUnavailable.rawValue, "DEVICE_KEY_UNAVAILABLE")
        XCTAssertEqual(PayabliErrorCode.attestationNotSupported.rawValue, "ATTESTATION_NOT_SUPPORTED")
    }

    func testTheCategoriesAreTheEightRemedies() {
        XCTAssertEqual(
            Set(PayabliErrorCategory.allCases),
            [.credential, .retryLater, .outcomeUnknown, .configuration, .invalidRequest, .declined, .device, .internal]
        )
    }
}
