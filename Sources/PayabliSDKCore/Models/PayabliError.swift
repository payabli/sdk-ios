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
public protocol PayabliError: Error, Sendable {
    /// Machine-readable code.
    var code: PayabliErrorCode { get }

    /// Human-readable short description.
    var reason: String { get }

    /// Optional detailed explanation.
    var detail: String? { get }
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

    public var code: PayabliErrorCode { .validation }
    public var reason: String { title ?? "Validation failed" }

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

    public var code: PayabliErrorCode { .unknown }
    public var reason: String { title ?? "Internal server error" }
}

/// HTTP 402 declined payment. See PRD §8.1.1 "Declined Response".
public struct PayabliDeclineError: PayabliError, Decodable {
    public let rawCode: String
    public let reason: String
    public let explanation: String?
    public let action: String?

    public var code: PayabliErrorCode { .unknown }
    public var detail: String? { explanation }

    enum CodingKeys: String, CodingKey {
        case reason, explanation, action
        case rawCode = "code"
    }
}

/// Umbrella error for payment-processing flows. Host apps switch on this to
/// distinguish decline, validation, server, or generic errors.
public enum PayabliPaymentError: Error, Sendable {
    case decline(PayabliDeclineError)
    case validation(PayabliValidationError)
    case server(PayabliServerError)
    case generic(PayabliGenericError)

    public var asPayabliError: any PayabliError {
        switch self {
        case .decline(let err): return err
        case .validation(let err): return err
        case .server(let err): return err
        case .generic(let err): return err
        }
    }
}
