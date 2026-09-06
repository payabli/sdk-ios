import Foundation

/// HTTP 429. The caller sent more requests than the service currently accepts.
///
/// Its own type rather than a server error, because the two are different conditions: this one is about
/// the caller's own rate and clears on its own, and a retry policy treating them alike is a coincidence
/// rather than a reason to merge them.
public struct PayabliRateLimitError: PayabliError, PayabliRetryAfter {
    public let retryAfter: TimeInterval?

    public var code: PayabliErrorCode {
        .rateLimited
    }

    public var reason: String {
        "Too many requests (429)"
    }

    public var detail: String? {
        nil
    }

    public init(retryAfter: TimeInterval? = nil) {
        self.retryAfter = retryAfter
    }
}
