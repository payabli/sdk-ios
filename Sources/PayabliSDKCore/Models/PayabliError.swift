import Foundation

/// Platform-aligned error codes from PRD §8 "Error Codes".
public enum PayabliErrorType: String, Sendable, CaseIterable {
    case missingToken = "MISSING_TOKEN"
    case tokenExpired = "TOKEN_EXPIRED"
    case tokenMalformed = "TOKEN_MALFORMED"

    /// The host's `tokenProvider` returned no token the SDK could use. ``PayabliError/detail`` names
    /// the specific failure. The SDK does not retry on this code; a subsequent SDK call invokes the
    /// callback again.
    case tokenProviderFailed = "TOKEN_PROVIDER_FAILED"
    case invalidSignature = "INVALID_SIGNATURE"
    case permissionDenied = "PERMISSION_DENIED"
    case sessionBurned = "SESSION_BURNED"

    /// HTTP 402, an issuer decline.
    ///
    /// Telling this apart from ``unknown`` is what lets a retry policy say "never retry a decline"
    /// without matching on prose.
    case paymentDeclined = "PAYMENT_DECLINED"

    /// The service could not process the request: an HTTP 5xx, or an answer whose own response code
    /// reports a problem rather than a refusal.
    ///
    /// A classification and not a licence to repeat: on a money-moving call the request may already have
    /// been executed, so a repeat without the original key can take the payment again. Whether an
    /// operation is safe to repeat is the operation's to say.
    case serverError = "SERVER_ERROR"

    /// HTTP 429, and the one status whose correct handling is unreachable without a code of its own:
    /// folded into ``unknown`` it could never be retried, because an unclassified status must not be.
    ///
    /// Safe to repeat, unlike a server error: the service refused to act rather than failing while
    /// acting, so nothing was executed.
    case rateLimited = "RATE_LIMITED"

    /// HTTP 409. The request conflicts with the state the service holds.
    ///
    /// Says no more than the status does, because the status mapping serves every route. What a
    /// conflict means is the route's to say: on a money-moving one it is a repeat the service refused,
    /// which settles what happens to the key and leaves the payment's outcome open. Reading that
    /// meaning in here would give a conflict on any other route a sense it has not earned.
    case conflict = "CONFLICT"

    // Client-side error codes (not from the API).
    case invalidConfiguration = "INVALID_CONFIGURATION"
    case networkError = "NETWORK_ERROR"
    case decodingError = "DECODING_ERROR"
    case userCancelled = "USER_CANCELLED"
    case validation = "VALIDATION_ERROR"
    case unknown = "UNKNOWN"
    case sdkInternalError = "SDK_INTERNAL_ERROR"
    case sessionNotInitialized = "SESSION_NOT_INITIALIZED"

    // Card-present.
    case deviceKeyUnavailable = "DEVICE_KEY_UNAVAILABLE"
    case deviceSetupUnsupported = "DEVICE_SETUP_UNSUPPORTED"
    case deviceServicesOutdated = "DEVICE_SERVICES_OUTDATED"
    case devicePendingActivation = "DEVICE_PENDING_ACTIVATION"
    case deviceSetupRequired = "DEVICE_SETUP_REQUIRED"
    case deviceSetupRefused = "DEVICE_SETUP_REFUSED"
    case deviceSetupUnavailable = "DEVICE_SETUP_UNAVAILABLE"
    case deviceSetupNotConfigured = "DEVICE_SETUP_NOT_CONFIGURED"
    case entryPointRefused = "ENTRY_POINT_REFUSED"
    case readerCredentialsUnusable = "READER_CREDENTIALS_UNUSABLE"
    case deviceOSUnsupported = "DEVICE_OS_UNSUPPORTED"
    case deviceHardwareUnsupported = "DEVICE_HARDWARE_UNSUPPORTED"
    case termsNotAccepted = "TERMS_NOT_ACCEPTED"
    case cardPresentNotEnabled = "CARD_PRESENT_NOT_ENABLED"
    case readerDeviceRefused = "READER_DEVICE_REFUSED"
    case readerUnavailable = "READER_UNAVAILABLE"
    case readerSessionExpired = "READER_SESSION_EXPIRED"
    case tapNotCompleted = "TAP_NOT_COMPLETED"
    case paymentNotOpened = "PAYMENT_NOT_OPENED"
    case cardDeclined = "CARD_DECLINED"
    case paymentOutcomeUnknown = "PAYMENT_OUTCOME_UNKNOWN"
    case paymentNotClosed = "PAYMENT_NOT_CLOSED"
    case activationCodeMalformed = "ACTIVATION_CODE_MALFORMED"
    case activationCodeIncorrect = "ACTIVATION_CODE_INCORRECT"
    case activationCodeExpired = "ACTIVATION_CODE_EXPIRED"
    case activationAttemptsExhausted = "ACTIVATION_ATTEMPTS_EXHAUSTED"
    case activationCodeNotIssued = "ACTIVATION_CODE_NOT_ISSUED"
    case deviceNotPending = "DEVICE_NOT_PENDING"
    case terminalNotReady = "TERMINAL_NOT_READY"
    case tooManyOpenCharges = "TOO_MANY_OPEN_CHARGES"
    case paymentNotHeld = "PAYMENT_NOT_HELD"
    case deviceIdentityUnavailable = "DEVICE_IDENTITY_UNAVAILABLE"
}

/// What a host does about a failure. Each ``PayabliErrorType`` belongs to one.
public enum PayabliErrorCategory: String, Sendable, CaseIterable {
    /// The SDK could not obtain or use a credential, a token or this device's setup. The SDK asks
    /// the token provider again on the next call, so a provider that can return a working token
    /// repairs it. A session or a device setup that has ended, which the state reports, is
    /// established again by calling `initialize`.
    case credential = "CREDENTIAL"

    /// The same call may work later.
    case retryLater = "RETRY_LATER"

    /// The call may have taken effect; check before repeating it.
    case outcomeUnknown = "OUTCOME_UNKNOWN"

    /// Someone changes the setup.
    case configuration = "CONFIGURATION"

    /// The request has to change.
    case invalidRequest = "INVALID_REQUEST"

    /// Do not repeat it.
    case declined = "DECLINED"

    /// This handset cannot do it.
    case device = "DEVICE"

    /// Report it.
    case `internal` = "INTERNAL"
}

/// The catalog: one number, message and category per code, the same on every platform the SDK ships on.
/// Numbers are allocated by area, core in the 1000s and card-present in the 3000s, and are never reused.
public extension PayabliErrorType {
    var number: Int {
        switch self {
        case .missingToken: 1001
        case .tokenExpired: 1002
        case .tokenMalformed: 1003
        case .tokenProviderFailed: 1004
        case .invalidSignature: 1005
        case .permissionDenied: 1006
        case .sessionBurned: 1007
        case .paymentDeclined: 1008
        case .serverError: 1009
        case .rateLimited: 1010
        case .conflict: 1011
        case .invalidConfiguration: 1012
        case .networkError: 1013
        case .decodingError: 1014
        case .userCancelled: 1015
        case .validation: 1016
        case .unknown: 1017
        case .sdkInternalError: 1018
        case .sessionNotInitialized: 1019
        case .deviceKeyUnavailable: 3001
        case .deviceSetupUnsupported: 3002
        case .deviceServicesOutdated: 3003
        case .devicePendingActivation: 3004
        case .deviceSetupRequired: 3005
        case .deviceSetupRefused: 3006
        case .deviceSetupUnavailable: 3007
        case .deviceSetupNotConfigured: 3008
        case .entryPointRefused: 3009
        case .readerCredentialsUnusable: 3010
        case .deviceOSUnsupported: 3011
        case .deviceHardwareUnsupported: 3012
        case .termsNotAccepted: 3013
        case .cardPresentNotEnabled: 3014
        case .readerDeviceRefused: 3015
        case .readerUnavailable: 3016
        case .readerSessionExpired: 3017
        case .tapNotCompleted: 3018
        case .paymentNotOpened: 3019
        case .cardDeclined: 3020
        case .paymentOutcomeUnknown: 3021
        case .paymentNotClosed: 3022
        case .activationCodeMalformed: 3023
        case .activationCodeIncorrect: 3024
        case .activationCodeExpired: 3025
        case .activationAttemptsExhausted: 3026
        case .activationCodeNotIssued: 3027
        case .deviceNotPending: 3028
        case .terminalNotReady: 3029
        case .tooManyOpenCharges: 3030
        case .paymentNotHeld: 3031
        case .deviceIdentityUnavailable: 3033
        }
    }

    /// Fixed SDK text. The service's own words stay in ``PayabliError/reason`` and ``PayabliError/detail``.
    var message: String {
        switch self {
        case .missingToken: "No access token is available."
        case .tokenExpired: "The access token expired or was rejected."
        case .tokenMalformed: "The access token could not be read."
        case .tokenProviderFailed: "The token provider did not return a usable token."
        case .invalidSignature: "The request signature was rejected."
        case .permissionDenied: "The credentials are not permitted to make this request."
        case .sessionBurned: "The session can no longer be used."
        case .paymentDeclined: "The payment was declined."
        case .serverError: "The service could not process the request."
        case .rateLimited: "Too many requests. Try again later."
        case .conflict: "The request conflicts with the state the service holds."
        case .invalidConfiguration: "The SDK is not configured correctly."
        case .networkError: "The service could not be reached."
        case .decodingError: "The response could not be read."
        case .userCancelled: "The person cancelled."
        case .validation: "The request was refused as invalid."
        case .unknown: "An unexpected error occurred."
        case .sdkInternalError: "The SDK failed before the request was sent."
        case .sessionNotInitialized: "The session has not been initialized."
        case .deviceKeyUnavailable: "This device's secure storage is unavailable."
        case .deviceSetupUnsupported: "This device cannot be set up for card-present payments."
        case .deviceServicesOutdated: "Google Play on this device must be installed, updated or signed in."
        case .devicePendingActivation: "This device is waiting for its activation code."
        case .deviceSetupRequired: "This device must be set up again."
        case .deviceSetupRefused: "This device was refused during setup."
        case .deviceSetupUnavailable: "Device setup is temporarily unavailable."
        case .deviceSetupNotConfigured: "Device setup is not configured for this app or environment."
        case .entryPointRefused: "The entry point is not available for this request."
        case .readerCredentialsUnusable: "The card reader's configuration is incomplete."
        case .deviceOSUnsupported: "This device's operating system version cannot take contactless payments."
        case .deviceHardwareUnsupported: "This device cannot take contactless payments."
        case .termsNotAccepted: "The merchant has not accepted the Tap to Pay terms."
        case .cardPresentNotEnabled: "Card-present payments are not enabled for this paypoint."
        case .readerDeviceRefused: "The card reader refused this device."
        case .readerUnavailable: "The card reader could not be started."
        case .readerSessionExpired: "The card reader session expired."
        case .tapNotCompleted: "The card read did not complete."
        case .paymentNotOpened: "The service did not open the payment."
        case .cardDeclined: "The card was declined."
        case .paymentOutcomeUnknown: "The payment's outcome could not be confirmed."
        case .paymentNotClosed: "The payment could not be closed."
        case .activationCodeMalformed: "The activation code must be six digits."
        case .activationCodeIncorrect: "The activation code is incorrect."
        case .activationCodeExpired: "The activation code has expired."
        case .activationAttemptsExhausted: "Too many incorrect activation codes were entered."
        case .activationCodeNotIssued: "No activation code has been issued for this device."
        case .deviceNotPending: "This device is not waiting for activation."
        case .terminalNotReady: "The terminal is not ready for this call."
        case .tooManyOpenCharges: "Too many charges are waiting to be resolved."
        case .paymentNotHeld: "No captured payment is held under that identifier."
        case .deviceIdentityUnavailable: "This device cannot be identified."
        }
    }

    var category: PayabliErrorCategory {
        switch self {
        case .missingToken, .tokenExpired, .tokenMalformed, .tokenProviderFailed, .invalidSignature, .sessionBurned,
             .deviceSetupRequired:
            .credential
        case .permissionDenied, .invalidConfiguration, .deviceServicesOutdated, .devicePendingActivation,
             .deviceSetupNotConfigured, .entryPointRefused, .readerCredentialsUnusable, .termsNotAccepted,
             .cardPresentNotEnabled, .activationCodeExpired, .activationAttemptsExhausted, .activationCodeNotIssued:
            .configuration
        case .paymentDeclined, .paymentNotOpened, .cardDeclined:
            .declined
        case .serverError, .networkError, .decodingError, .userCancelled, .unknown, .conflict, .tapNotCompleted,
             .paymentOutcomeUnknown, .paymentNotClosed:
            .outcomeUnknown
        case .rateLimited, .deviceKeyUnavailable, .deviceSetupUnavailable, .readerUnavailable, .readerSessionExpired:
            .retryLater
        case .validation, .sessionNotInitialized, .activationCodeMalformed, .activationCodeIncorrect, .deviceNotPending, .terminalNotReady,
             .tooManyOpenCharges, .paymentNotHeld:
            .invalidRequest
        case .deviceSetupUnsupported, .deviceSetupRefused, .deviceOSUnsupported, .deviceHardwareUnsupported,
             .readerDeviceRefused, .deviceIdentityUnavailable:
            .device
        case .sdkInternalError:
            .internal
        }
    }
}

/// Root error type for PayabliSDK.
///
/// All SDK-originated errors conform to `PayabliError`. Components may extend
/// this with domain-specific error types (e.g. `TapToPayError`).
///
/// See PRD §8 and §20.2.
public protocol PayabliError: LocalizedError, Sendable {
    /// The catalog entry. A host switches on it.
    var type: PayabliErrorType { get }

    /// Human-readable short description.
    var reason: String { get }

    /// Optional detailed explanation.
    var detail: String? { get }
}

public extension PayabliError {
    /// The catalog number.
    var code: Int {
        type.number
    }

    /// What a host does about the failure.
    var category: PayabliErrorCategory {
        type.category
    }

    /// Fixed SDK text, the same on every platform.
    var message: String {
        type.message
    }

    /// What `localizedDescription` returns, which is what a host app puts in
    /// front of a merchant. Without this every one of these reads "The
    /// operation couldn't be completed. (Module.Type error N.)", and the
    /// `reason` the SDK went to the trouble of parsing never leaves the SDK.
    var errorDescription: String? {
        guard let detail, !detail.isEmpty, detail != reason else { return reason }
        return "\(reason): \(detail)"
    }
}

/// A generic transport or client-side error.
public struct PayabliGenericError: PayabliError {
    public let type: PayabliErrorType
    public let reason: String
    public let detail: String?
    public let underlying: Error?

    public init(
        type: PayabliErrorType,
        reason: String,
        detail: String? = nil,
        underlying: Error? = nil
    ) {
        self.type = type
        self.reason = reason
        self.detail = detail
        self.underlying = underlying
    }
}

// MARK: - RFC 7807 validation / server errors

/// Field-level validation error entry in an RFC 7807 response.
public struct PayabliFieldError: Decodable, Sendable {
    public let message: String
    public let suggestion: String?

    /// Reads both shapes the platform sends: a bare string becomes `message` with
    /// no suggestion, and the declared object decodes as-is. Both are live.
    public init(from decoder: any Decoder) throws {
        if let message = try? decoder.singleValueContainer().decode(String.self) {
            self.message = message
            suggestion = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        suggestion = try container.decodeIfPresent(String.self, forKey: .suggestion)
    }

    enum CodingKeys: String, CodingKey {
        case message, suggestion
    }
}

/// HTTP 400 validation error (RFC 7807). See PRD §8.1.1 "Validation Error".
public struct PayabliValidationError: PayabliError, Decodable {
    public let problemType: String?
    public let title: String?
    public let status: Int?
    public let detail: String?
    public let instance: String?
    public let rawCode: String?
    public let errors: [String: [PayabliFieldError]]?
    public let token: String?

    public var type: PayabliErrorType {
        .validation
    }

    public var reason: String {
        title ?? "Validation failed"
    }

    /// Appends each rejected field and the message the server sent for it, which
    /// is the part that says what to correct. The title alone is usually
    /// "Validation failed", which tells a merchant nothing.
    ///
    /// `suggestion` is left out: it can quote a corrected value, and a value is
    /// what this must not carry.
    ///
    /// For display. A message is server text and can echo request data, so it
    /// belongs in front of a person rather than in a log, which is the rule the
    /// sibling platform states on its own error root.
    public var errorDescription: String? {
        var parts = [reason]
        if let detail, !detail.isEmpty, detail != reason {
            parts.append(detail)
        }
        for (field, entries) in (errors ?? [:]).sorted(by: { $0.key < $1.key }) {
            for entry in entries {
                parts.append("\(field): \(entry.message)")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// `errors` decodes separately because the synthesised decoder throws on a
    /// present-but-mismatched value, taking `title`, `detail` and `type` with it.
    /// One unreadable entry drops the whole map.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        problemType = try container.decodeIfPresent(String.self, forKey: .problemType)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        status = try container.decodeIfPresent(Int.self, forKey: .status)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        instance = try container.decodeIfPresent(String.self, forKey: .instance)
        rawCode = try container.decodeIfPresent(String.self, forKey: .rawCode)
        token = try container.decodeIfPresent(String.self, forKey: .token)
        errors = try? container.decodeIfPresent([String: [PayabliFieldError]].self, forKey: .errors)
    }

    /// The empty error, for a 400 whose body will not decode at all.
    init() {
        problemType = nil
        title = nil
        status = nil
        detail = nil
        instance = nil
        rawCode = nil
        errors = nil
        token = nil
    }

    enum CodingKeys: String, CodingKey {
        case problemType = "type"
        case title, status, detail, instance, errors, token
        case rawCode = "code"
    }
}

/// HTTP 500 server error. See PRD §8.1.1 "Server Error".
public struct PayabliServerError: PayabliError, Decodable, PayabliRetryAfter {
    public let problemType: String?
    public let title: String?
    public let status: Int?
    public let detail: String?
    public let instance: String?

    /// The status the response itself carried, which is not always the `status` its body names.
    public let httpStatus: Int?

    public let retryAfter: TimeInterval?

    public var type: PayabliErrorType {
        .serverError
    }

    public var reason: String {
        title ?? "Internal server error"
    }

    /// The empty error, for a 5xx whose body will not decode at all.
    init(httpStatus: Int? = nil, retryAfter: TimeInterval? = nil) {
        problemType = nil
        title = nil
        status = nil
        detail = nil
        instance = nil
        self.httpStatus = httpStatus
        self.retryAfter = retryAfter
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        problemType = try container.decodeIfPresent(String.self, forKey: .problemType)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        status = try container.decodeIfPresent(Int.self, forKey: .status)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        instance = try container.decodeIfPresent(String.self, forKey: .instance)
        httpStatus = nil
        retryAfter = nil
    }

    private init(
        problemType: String?,
        title: String?,
        status: Int?,
        detail: String?,
        instance: String?,
        httpStatus: Int?,
        retryAfter: TimeInterval?
    ) {
        self.problemType = problemType
        self.title = title
        self.status = status
        self.detail = detail
        self.instance = instance
        self.httpStatus = httpStatus
        self.retryAfter = retryAfter
    }

    /// The same error, carrying the two things only the response envelope knows.
    func carrying(httpStatus: Int, retryAfter: TimeInterval?) -> PayabliServerError {
        PayabliServerError(
            problemType: problemType,
            title: title,
            status: status,
            detail: detail,
            instance: instance,
            httpStatus: httpStatus,
            retryAfter: retryAfter
        )
    }

    enum CodingKeys: String, CodingKey {
        case problemType = "type"
        case title, status, detail, instance
    }
}

/// HTTP 402 declined payment. See PRD §8.1.1 "Declined Response".
public struct PayabliDeclineError: PayabliError, Decodable {
    /// The processor decline code, for example `D0329`. `nil` when the body carried none.
    public let rawCode: String?
    public let reason: String
    public let explanation: String?
    public let action: String?

    static let defaultReason = "Payment declined (402)"

    public var type: PayabliErrorType {
        .paymentDeclined
    }

    public var detail: String? {
        explanation
    }

    /// A decline carries the one thing the payer can act on, so `action` is
    /// worth more here than anywhere else and the default drops it.
    public var errorDescription: String? {
        var parts = [reason]
        if let explanation, !explanation.isEmpty, explanation != reason {
            parts.append(explanation)
        }
        if let action, !action.isEmpty {
            parts.append(action)
        }
        return parts.joined(separator: " · ")
    }

    /// A missing `code` or `reason` degrades that field and does not fail the decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawCode = try container.decodeIfPresent(String.self, forKey: .rawCode)
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? Self.defaultReason
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
        action = try container.decodeIfPresent(String.self, forKey: .action)
    }

    /// The empty decline, for a 402 whose body will not decode at all.
    init() {
        rawCode = nil
        reason = Self.defaultReason
        explanation = nil
        action = nil
    }

    enum CodingKeys: String, CodingKey {
        case reason, explanation, action
        case rawCode = "code"
    }
}

/// Umbrella error for payment-processing flows. Host apps switch on this to
/// distinguish decline, validation, server, or generic errors.
///
/// A `PayabliError` as well, delegating to whichever error it holds, because this
/// is the type `mapPayabliHTTPError` throws: without the conformance every
/// `error as? any PayabliError` in the SDK, in a host app and in this SDK's own
/// documentation misses the failures it was written for, and falls back to
/// `String(describing:)`, which renders each stored property of the wrapped error.
public enum PayabliPaymentError: PayabliError, PayabliRetryAfter, Sendable {
    case decline(PayabliDeclineError)
    case validation(PayabliValidationError)
    case server(PayabliServerError)
    case generic(PayabliGenericError)

    public var asPayabliError: any PayabliError {
        switch self {
        case let .decline(err): return err
        case let .validation(err): return err
        case let .server(err): return err
        case let .generic(err): return err
        }
    }

    public var type: PayabliErrorType {
        asPayabliError.type
    }

    public var reason: String {
        asPayabliError.reason
    }

    public var detail: String? {
        asPayabliError.detail
    }

    /// Defers to the wrapped error for the same reason `code` does: a `catch` or a cast written against
    /// `PayabliRetryAfter` would otherwise miss every 5xx, which is the only case that carries one.
    public var retryAfter: TimeInterval? {
        (asPayabliError as? any PayabliRetryAfter)?.retryAfter
    }

    /// Defers to the wrapped error. An enum that only conforms to `Error`
    /// renders as its case index, so this surfaced as
    /// "PayabliPaymentError error 1" with the parsed reason discarded.
    public var errorDescription: String? {
        asPayabliError.errorDescription
    }
}
