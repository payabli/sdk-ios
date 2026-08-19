import Foundation

/// Platform-aligned error codes from PRD §8 "Error Codes".
public enum PayabliErrorCode: String, Sendable {
    case missingToken = "MISSING_TOKEN"
    case tokenExpired = "TOKEN_EXPIRED"
    case tokenMalformed = "TOKEN_MALFORMED"
    case invalidSignature = "INVALID_SIGNATURE"
    case permissionDenied = "PERMISSION_DENIED"
    case sessionBurned = "SESSION_BURNED"

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

    enum CodingKeys: String, CodingKey {
        case type, title, status, detail, instance, errors, token
        case rawCode = "code"
    }
}

/// HTTP 500 server error. See PRD §8.1.1 "Server Error".
public struct PayabliServerError: PayabliError, Decodable {
    public let title: String?
    public let status: Int?
    public let detail: String?
    public let instance: String?

    public var code: PayabliErrorCode {
        .unknown
    }

    public var reason: String {
        title ?? "Internal server error"
    }
}

/// HTTP 402 declined payment. See PRD §8.1.1 "Declined Response".
public struct PayabliDeclineError: PayabliError, Decodable {
    public let rawCode: String
    public let reason: String
    public let explanation: String?
    public let action: String?

    public var code: PayabliErrorCode {
        .unknown
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

    enum CodingKeys: String, CodingKey {
        case reason, explanation, action
        case rawCode = "code"
    }
}

/// Umbrella error for payment-processing flows. Host apps switch on this to
/// distinguish decline, validation, server, or generic errors.
public enum PayabliPaymentError: LocalizedError, Sendable {
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

    /// Defers to the wrapped error. An enum that only conforms to `Error`
    /// renders as its case index, so this surfaced as
    /// "PayabliPaymentError error 1" with the parsed reason discarded.
    public var errorDescription: String? {
        asPayabliError.errorDescription
    }
}
