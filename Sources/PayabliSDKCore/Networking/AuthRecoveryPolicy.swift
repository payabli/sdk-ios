import Foundation

/// What counts as the credential being refused, and what a caller is told when replacing it did not help.
///
/// The seam exists so a capability whose routes refuse a stale credential with something other than a 401
/// can say so, without every route inheriting that reading. Widening it widens the refresh; it does not
/// widen the replay, which `AuthenticatedTransport` decides separately and for a different reason.
protocol AuthRecoveryPolicy: Sendable {
    /// Whether `response` says the credential was refused.
    func isCredentialRejection(_ response: PayabliResponse) -> Bool
}

extension AuthRecoveryPolicy {
    /// What a caller gets when a refreshed credential was refused too.
    ///
    /// Not a protocol requirement, so it cannot be substituted. An implementation answering a retryable
    /// code here would make the retry layer above read a settled credential failure as transient and
    /// spend the whole policy on refresh-and-replay cycles.
    ///
    /// Carries no text from the response. A 401 body belongs to the service.
    func exhausted() -> PayabliGenericError {
        PayabliGenericError(code: .tokenExpired, reason: "Refresh token rejected")
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
