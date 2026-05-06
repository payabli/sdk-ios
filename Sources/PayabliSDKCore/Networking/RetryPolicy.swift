import Foundation

/// Retry policy for `PATCH /update/{paymentTransId}` (PRD §21.1).
///
/// - Max 3 attempts
/// - Base delay 1.0s, max 8.0s, 2× exponential
/// - Jitter 0–0.5s
/// - Retryable: 5xx + timeouts
/// - Non-retryable: 4xx (fail immediately)
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let multiplier: Double
    public let maxJitter: TimeInterval

    public static let `default` = RetryPolicy(
        maxAttempts: 3,
        baseDelay: 1.0,
        maxDelay: 8.0,
        multiplier: 2.0,
        maxJitter: 0.5
    )

    public init(
        maxAttempts: Int,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval,
        multiplier: Double,
        maxJitter: TimeInterval
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
        self.maxJitter = maxJitter
    }

    /// Delay before the given attempt (1-indexed). Attempt 1 returns 0 (no wait).
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 1 else { return 0 }
        let exponent = Double(attempt - 2)
        let backoff = min(baseDelay * pow(multiplier, exponent), maxDelay)
        let jitter = Double.random(in: 0...maxJitter)
        return backoff + jitter
    }

    /// Whether the given HTTP status code is retryable.
    public func isRetryable(statusCode: Int) -> Bool {
        // Retryable: 500, 502, 503, 504, generic 5xx, timeouts.
        // Non-retryable: 400, 401, 403, 404.
        switch statusCode {
        case 408: return true // request timeout
        case 500...599: return true
        default: return false
        }
    }
}

/// Executes an async operation with the given retry policy.
///
/// The operation receives the current attempt number (1-indexed). If it throws
/// a `RetryableError`, the policy applies backoff and retries up to
/// `policy.maxAttempts`. Other errors propagate immediately.
public struct RetryableError: Error {
    public let underlying: Error
    public init(_ underlying: Error) { self.underlying = underlying }
}

public enum Retry {
    public static func run<T: Sendable>(
        policy: RetryPolicy = .default,
        _ operation: @Sendable (_ attempt: Int) async throws -> T
    ) async throws -> T {
        var lastUnderlying: Error?
        for attempt in 1...policy.maxAttempts {
            let delay = policy.delay(forAttempt: attempt)
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            do {
                return try await operation(attempt)
            } catch let retryable as RetryableError {
                lastUnderlying = retryable.underlying
                if attempt == policy.maxAttempts { throw retryable.underlying }
                continue
            } catch {
                throw error
            }
        }
        throw lastUnderlying ?? PayabliGenericError(
            code: .networkError,
            reason: "Exhausted retries"
        )
    }
}
