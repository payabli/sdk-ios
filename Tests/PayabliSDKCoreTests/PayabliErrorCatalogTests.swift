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
        (.conflict, 1011, .outcomeUnknown, "The request conflicts with the state the service holds."),
        (.invalidConfiguration, 1012, .configuration, "The SDK is not configured correctly."),
        (.networkError, 1013, .outcomeUnknown, "The service could not be reached."),
        (.decodingError, 1014, .outcomeUnknown, "The response could not be read."),
        (.userCancelled, 1015, .outcomeUnknown, "The person cancelled."),
        (.validation, 1016, .invalidRequest, "The request was refused as invalid."),
        (.unknown, 1017, .outcomeUnknown, "An unexpected error occurred."),
        (.sdkInternalError, 1018, .internal, "The SDK failed before the request was sent."),
        (.deviceKeyUnavailable, 3001, .retryLater, "The device's key facility could not confirm this device's key."),
        (.attestationNotSupported, 3002, .device, "This device does not support app attestation."),
        (.attestationServicesOutdated, 3003, .configuration, "This device's attestation services must be installed or updated."),
        (.devicePendingActivation, 3004, .configuration, "This device is waiting for its activation code."),
        (.attestationRequired, 3005, .credential, "This device must be attested again."),
        (.attestationRefused, 3006, .device, "This device's attestation was refused."),
        (.attestationUnavailable, 3007, .retryLater, "Attestation is temporarily unavailable."),
        (.attestationNotConfigured, 3008, .configuration, "Attestation is not configured for this app or environment."),
        (.entryPointRefused, 3009, .configuration, "The entry point is not available for this request."),
        (.readerCredentialsUnusable, 3010, .configuration, "The card reader's configuration is incomplete."),
        (.deviceOSUnsupported, 3011, .device, "This device's operating system version cannot take contactless payments."),
        (.deviceHardwareUnsupported, 3012, .device, "This device cannot take contactless payments."),
        (.termsNotAccepted, 3013, .configuration, "The merchant has not accepted the Tap to Pay terms."),
        (.cardPresentNotEnabled, 3014, .configuration, "Card-present payments are not enabled for this paypoint."),
        (.readerDeviceRefused, 3015, .device, "The card reader refused this device."),
        (.readerUnavailable, 3016, .retryLater, "The card reader could not be started."),
        (.readerSessionExpired, 3017, .retryLater, "The card reader session expired."),
        (.tapNotCompleted, 3018, .outcomeUnknown, "The card read did not complete."),
        (.paymentNotOpened, 3019, .declined, "The service did not open the payment."),
        (.cardDeclined, 3020, .declined, "The card was declined."),
        (.paymentOutcomeUnknown, 3021, .outcomeUnknown, "The payment's outcome could not be confirmed."),
        (.paymentNotClosed, 3022, .outcomeUnknown, "The payment could not be closed."),
        (.activationCodeMalformed, 3023, .invalidRequest, "The activation code must be six digits."),
        (.activationCodeIncorrect, 3024, .invalidRequest, "The activation code is incorrect."),
        (.activationCodeExpired, 3025, .configuration, "The activation code has expired."),
        (.activationAttemptsExhausted, 3026, .configuration, "Too many incorrect activation codes were entered."),
        (.activationCodeNotIssued, 3027, .configuration, "No activation code has been issued for this device."),
        (.deviceNotPending, 3028, .invalidRequest, "This device is not waiting for activation."),
        (.terminalNotReady, 3029, .invalidRequest, "The terminal is not ready for this call."),
        (.tooManyOpenCharges, 3030, .invalidRequest, "Too many charges are waiting to be resolved."),
        (.paymentNotHeld, 3031, .invalidRequest, "No captured payment is held under that identifier.")
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
