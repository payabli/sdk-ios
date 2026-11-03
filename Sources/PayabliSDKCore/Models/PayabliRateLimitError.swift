import Foundation

/// HTTP 429. The caller sent more requests than the service currently accepts.
///
/// The condition is the caller's own rate, and it clears on its own.
public struct PayabliRateLimitError: PayabliError, PayabliRetryAfter {
    public let retryAfter: TimeInterval?
    public let httpStatus: Int?
    public let rawCode: String?

    public var type: PayabliErrorType {
        .rateLimited
    }

    public var reason: String {
        "Too many requests (429)"
    }

    public var detail: String? {
        nil
    }

    /// A rate limit no response was read for, so it carries no status and no code.
    ///
    /// - Parameter retryAfter: the delay before the next attempt, if one is known.
    public init(retryAfter: TimeInterval? = nil) {
        self.init(retryAfter: retryAfter, httpStatus: nil, rawCode: nil)
    }

    /// A rate limit read from a response.
    ///
    /// - Parameter retryAfter: the delay the response's `Retry-After` header named, if any.
    /// - Parameter httpStatus: the response's status line.
    /// - Parameter rawCode: the code the response's body named, when it named one.
    package init(retryAfter: TimeInterval?, httpStatus: Int?, rawCode: String?) {
        self.retryAfter = retryAfter
        self.httpStatus = httpStatus
        self.rawCode = rawCode
    }
}
