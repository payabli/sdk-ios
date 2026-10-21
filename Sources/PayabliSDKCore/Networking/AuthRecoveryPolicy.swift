import Foundation

/// What counts as the credential being refused, asked of every request by `AuthenticatedTransport`, which decides the
/// replay itself so widening one never widens the other. Only this module's tests substitute a policy; a route that
/// refuses recovery says so per request (`PayabliRequest.pinsCredential`).
protocol AuthRecoveryPolicy: Sendable {
    /// Whether `response` says the credential was refused.
    ///
    /// - Parameter response: the answered response, whose status the policy reads.
    /// - Returns: whether that status says the credential was refused, so a new one is worth minting.
    func isCredentialRejection(_ response: PayabliResponse) -> Bool
}

extension AuthRecoveryPolicy {
    /// What a caller gets when a refreshed credential was refused too.
    /// Carries no text from the response: a 401 body belongs to the service.
    /// A retryable code here would make the retry layer read a settled credential failure as transient.
    ///
    /// - Returns: the ``PayabliErrorType/tokenExpired`` error with no service text.
    func exhausted() -> PayabliGenericError {
        PayabliGenericError(type: .tokenExpired, reason: "Refresh token rejected")
    }
}

/// A 401 and nothing else.
///
/// A 403 is a decision about what this credential may do, a 410 is a session that is gone and a 402 is a
/// decline. A different credential does not change any of them.
struct DefaultAuthRecoveryPolicy: AuthRecoveryPolicy {
    func isCredentialRejection(_ response: PayabliResponse) -> Bool {
        response.statusCode == 401
    }
}
