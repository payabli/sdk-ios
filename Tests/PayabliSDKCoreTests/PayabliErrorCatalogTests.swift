import PayabliSDKCore
import XCTest

/// The published catalog: every type's wire name, number, category and message, exactly as both SDKs declare them.
final class PayabliErrorCatalogTests: XCTestCase {
    private typealias Row = (PayabliErrorType, String, Int, PayabliErrorCategory, String)

    private let table: [Row] = [
        (.missingToken, "MISSING_TOKEN", 1001, .credential, "No access token is available."),
        (.tokenExpired, "TOKEN_EXPIRED", 1002, .credential, "The access token expired or was rejected."),
        (.tokenMalformed, "TOKEN_MALFORMED", 1003, .credential, "The access token could not be read."),
        (.tokenProviderFailed, "TOKEN_PROVIDER_FAILED", 1004, .credential, "The token provider did not return a usable token."),
        (.invalidSignature, "INVALID_SIGNATURE", 1005, .credential, "The request signature was rejected."),
        (.permissionDenied, "PERMISSION_DENIED", 1006, .configuration, "The credentials are not permitted to make this request."),
        (.sessionBurned, "SESSION_BURNED", 1007, .credential, "The session can no longer be used."),
        (.paymentDeclined, "PAYMENT_DECLINED", 1008, .declined, "The payment was declined."),
        (.serverError, "SERVER_ERROR", 1009, .outcomeUnknown, "The service could not process the request."),
        (.rateLimited, "RATE_LIMITED", 1010, .retryLater, "Too many requests. Try again later."),
        (.conflict, "CONFLICT", 1011, .outcomeUnknown, "The request conflicts with the state the service holds."),
        (.invalidConfiguration, "INVALID_CONFIGURATION", 1012, .configuration, "The SDK is not configured correctly."),
        (.networkError, "NETWORK_ERROR", 1013, .outcomeUnknown, "The service could not be reached."),
        (.decodingError, "DECODING_ERROR", 1014, .outcomeUnknown, "The response could not be read."),
        (.userCancelled, "USER_CANCELLED", 1015, .outcomeUnknown, "The person cancelled."),
        (.validation, "VALIDATION_ERROR", 1016, .invalidRequest, "The request was refused as invalid."),
        (.unknown, "UNKNOWN", 1017, .outcomeUnknown, "An unexpected error occurred."),
        (.sdkInternalError, "SDK_INTERNAL_ERROR", 1018, .internal, "The SDK failed before the request was sent."),
        (
            .deviceKeyUnavailable,
            "DEVICE_KEY_UNAVAILABLE",
            3001,
            .retryLater,
            "This device's secure storage could not be read."
        ),
        (.deviceSetupUnsupported, "DEVICE_SETUP_UNSUPPORTED", 3002, .device, "This device cannot be set up for card-present payments."),
        (
            .deviceServicesOutdated,
            "DEVICE_SERVICES_OUTDATED",
            3003,
            .configuration,
            "Google Play on this device must be installed, updated or signed in."
        ),
        (.devicePendingActivation, "DEVICE_PENDING_ACTIVATION", 3004, .configuration, "This device is waiting for its activation code."),
        (.deviceSetupRequired, "DEVICE_SETUP_REQUIRED", 3005, .credential, "This device must be set up again."),
        (.deviceSetupRefused, "DEVICE_SETUP_REFUSED", 3006, .device, "This device was refused during setup."),
        (.deviceSetupUnavailable, "DEVICE_SETUP_UNAVAILABLE", 3007, .retryLater, "Device setup is temporarily unavailable."),
        (
            .deviceSetupNotConfigured,
            "DEVICE_SETUP_NOT_CONFIGURED",
            3008,
            .configuration,
            "Device setup is not configured for this app or environment."
        ),
        (.entryPointRefused, "ENTRY_POINT_REFUSED", 3009, .configuration, "The entry point is not available for this request."),
        (.readerCredentialsUnusable, "READER_CREDENTIALS_UNUSABLE", 3010, .configuration, "The card reader's configuration is incomplete."),
        (
            .deviceOSUnsupported,
            "DEVICE_OS_UNSUPPORTED",
            3011,
            .device,
            "This device's operating system version cannot take contactless payments."
        ),
        (.deviceHardwareUnsupported, "DEVICE_HARDWARE_UNSUPPORTED", 3012, .device, "This device cannot take contactless payments."),
        (.termsNotAccepted, "TERMS_NOT_ACCEPTED", 3013, .configuration, "The merchant has not accepted the Tap to Pay terms."),
        (
            .cardPresentNotEnabled,
            "CARD_PRESENT_NOT_ENABLED",
            3014,
            .configuration,
            "Card-present payments are not enabled for this paypoint."
        ),
        (.readerDeviceRefused, "READER_DEVICE_REFUSED", 3015, .device, "The card reader refused this device."),
        (.readerUnavailable, "READER_UNAVAILABLE", 3016, .retryLater, "The card reader could not be started."),
        (.readerSessionExpired, "READER_SESSION_EXPIRED", 3017, .retryLater, "The card reader session expired."),
        (.tapNotCompleted, "TAP_NOT_COMPLETED", 3018, .outcomeUnknown, "The card read did not complete."),
        (.paymentNotOpened, "PAYMENT_NOT_OPENED", 3019, .declined, "The service did not open the payment."),
        (.cardDeclined, "CARD_DECLINED", 3020, .declined, "The card was declined."),
        (.paymentOutcomeUnknown, "PAYMENT_OUTCOME_UNKNOWN", 3021, .outcomeUnknown, "The payment's outcome could not be confirmed."),
        (.paymentNotClosed, "PAYMENT_NOT_CLOSED", 3022, .outcomeUnknown, "The payment could not be closed."),
        (.activationCodeMalformed, "ACTIVATION_CODE_MALFORMED", 3023, .invalidRequest, "The activation code must be six digits."),
        (.activationCodeIncorrect, "ACTIVATION_CODE_INCORRECT", 3024, .invalidRequest, "The activation code is incorrect."),
        (.activationCodeExpired, "ACTIVATION_CODE_EXPIRED", 3025, .configuration, "The activation code has expired."),
        (
            .activationAttemptsExhausted,
            "ACTIVATION_ATTEMPTS_EXHAUSTED",
            3026,
            .configuration,
            "Too many incorrect activation codes were entered."
        ),
        (
            .activationCodeNotIssued,
            "ACTIVATION_CODE_NOT_ISSUED",
            3027,
            .configuration,
            "No activation code has been issued for this device."
        ),
        (.deviceNotPending, "DEVICE_NOT_PENDING", 3028, .invalidRequest, "This device is not waiting for activation."),
        (.terminalNotReady, "TERMINAL_NOT_READY", 3029, .invalidRequest, "The terminal is not ready for this call."),
        (.tooManyOpenCharges, "TOO_MANY_OPEN_CHARGES", 3030, .invalidRequest, "Too many charges are waiting to be resolved."),
        (.paymentNotHeld, "PAYMENT_NOT_HELD", 3031, .invalidRequest, "No captured payment is held under that identifier."),
        (.deviceIdentityUnavailable, "DEVICE_IDENTITY_UNAVAILABLE", 3033, .device, "This device cannot be identified.")
    ]

    func testEveryTypeCarriesItsPublishedNameNumberCategoryAndMessage() {
        for (type, name, number, category, message) in table {
            XCTAssertEqual(type.rawValue, name, "\(type)")
            XCTAssertEqual(type.number, number, "\(type)")
            XCTAssertEqual(type.category, category, "\(type)")
            XCTAssertEqual(type.message, message, "\(type)")
        }
    }

    func testTheTableCoversEveryType() {
        XCTAssertEqual(Set(table.map(\.0)), Set(PayabliErrorType.allCases))
    }

    func testNoTwoCodesShareANumber() {
        let numbers = PayabliErrorType.allCases.map(\.number)
        XCTAssertEqual(Set(numbers).count, numbers.count)
    }

    func testTheCategoriesAreTheEightRemediesUnderTheirWireNames() {
        let names: [PayabliErrorCategory: String] = [
            .credential: "CREDENTIAL",
            .retryLater: "RETRY_LATER",
            .outcomeUnknown: "OUTCOME_UNKNOWN",
            .configuration: "CONFIGURATION",
            .invalidRequest: "INVALID_REQUEST",
            .declined: "DECLINED",
            .device: "DEVICE",
            .internal: "INTERNAL"
        ]
        XCTAssertEqual(Set(PayabliErrorCategory.allCases), Set(names.keys))
        for (category, name) in names {
            XCTAssertEqual(category.rawValue, name, "\(category)")
        }
    }
}
