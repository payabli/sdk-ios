import Foundation

/// Platform-aligned error codes from PRD §8 "Error Codes".
public enum PayabliErrorCode: String, Sendable, CaseIterable {
    case missingToken = "MISSING_TOKEN"
    case tokenExpired = "TOKEN_EXPIRED"
    case tokenMalformed = "TOKEN_MALFORMED"
    case invalidSignature = "INVALID_SIGNATURE"
    case permissionDenied = "PERMISSION_DENIED"
    case sessionBurned = "SESSION_BURNED"

    /// A payment the processor refused. Authoritative, so it is never retried, and telling it apart from
    /// `unknown` is what lets a retry policy say so without matching on prose.
    case paymentDeclined = "PAYMENT_DECLINED"

    /// A server-side fault. Transient, so it is retried, which is why it is not folded into `unknown`.
    case serverError = "SERVER_ERROR"

    /// Too many requests. The one code whose correct handling is unreachable without it: folded into
    /// `unknown` it becomes un-retryable, because an unclassified failure must never be retried.
    case rateLimited = "RATE_LIMITED"

    // Client-side error codes (not from the API).
    case invalidConfiguration = "INVALID_CONFIGURATION"
    case networkError = "NETWORK_ERROR"
    case decodingError = "DECODING_ERROR"
    case userCancelled = "USER_CANCELLED"
    case validation = "VALIDATION_ERROR"
    case unknown = "UNKNOWN"
}

/// Root error type for PayabliSDK.
///
/// All SDK-originated errors conform to `PayabliError`. Components may extend
/// this with domain-specific error types (e.g. `PayabliTTPError`).
///
/// See PRD §8 and §20.2.
public protocol PayabliError: LocalizedError, Sendable {
    /// Machine-readable code.
    var code: PayabliErrorCode { get }

    /// Human-readable short description.
    var reason: String { get }

    /// Optional detailed explanation.
    var detail: String? { get }
}

public extension PayabliError {
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
    public let code: PayabliErrorCode
    public let reason: String
    public let detail: String?
    public let underlying: Error?

    public init(
        code: PayabliErrorCode,
        reason: String,
        detail: String? = nil,
        underlying: Error? = nil
    ) {
        self.code = code
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
    public let type: String?
    public let title: String?
    public let status: Int?
    public let detail: String?
    public let instance: String?
    public let rawCode: String?
    public let errors: [String: [PayabliFieldError]]?
    public let token: String?

    public var code: PayabliErrorCode {
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
        type = try container.decodeIfPresent(String.self, forKey: .type)
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
        type = nil
        title = nil
        status = nil
        detail = nil
        instance = nil
        rawCode = nil
        errors = nil
        token = nil
    }

    enum CodingKeys: String, CodingKey {
        case type, title, status, detail, instance, errors, token
        case rawCode = "code"
    }
}

/// HTTP 500 server error. See PRD §8.1.1 "Server Error".
public struct PayabliServerError: PayabliError, Decodable, PayabliRetryAfter {
    public let title: String?
    public let status: Int?
    public let detail: String?
    public let instance: String?

    /// The status the response itself carried, which is not always the `status` its body names.
    public let httpStatus: Int?

    public let retryAfter: TimeInterval?

    public var code: PayabliErrorCode {
        .serverError
    }

    public var reason: String {
        title ?? "Internal server error"
    }

    /// The empty error, for a 5xx whose body will not decode at all.
    init(httpStatus: Int? = nil, retryAfter: TimeInterval? = nil) {
        title = nil
        status = nil
        detail = nil
        instance = nil
        self.httpStatus = httpStatus
        self.retryAfter = retryAfter
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        status = try container.decodeIfPresent(Int.self, forKey: .status)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        instance = try container.decodeIfPresent(String.self, forKey: .instance)
        httpStatus = nil
        retryAfter = nil
    }

    private init(
        title: String?,
        status: Int?,
        detail: String?,
        instance: String?,
        httpStatus: Int?,
        retryAfter: TimeInterval?
    ) {
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
            title: title,
            status: status,
            detail: detail,
            instance: instance,
            httpStatus: httpStatus,
            retryAfter: retryAfter
        )
    }

    enum CodingKeys: String, CodingKey {
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

    public var code: PayabliErrorCode {
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

    public var code: PayabliErrorCode {
        asPayabliError.code
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
