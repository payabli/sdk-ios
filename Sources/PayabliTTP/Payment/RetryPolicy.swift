import Foundation

/// Exponential backoff retry policy for transient network failures.
/// Used by the PaymentOrchestrator for critical-path retries.
struct RetryPolicy {

    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval

    init(maxAttempts: Int = 3, baseDelay: TimeInterval = 1.0, maxDelay: TimeInterval = 10.0) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// Execute an async operation with retry. Only retries on transient errors
    /// (network errors, 5xx status codes). Non-retryable errors are thrown immediately.
    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                guard isRetryable(error), attempt < maxAttempts - 1 else {
                    throw error
                }

                let delay = min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
                let jitter = Double.random(in: 0...0.5)
                try await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))
            }
        }

        throw lastError ?? PayabliTTPError.unknown("Retry exhausted")
    }

    private func isRetryable(_ error: Error) -> Bool {
        switch error {
        case PayabliTTPError.networkError:
            return true
        case PayabliTTPError.backendError(let statusCode, _):
            return statusCode >= 500
        default:
            return false
        }
    }
}
