import Foundation

/// What counts as the credential being refused, and what a caller is told when replacing it did not help.
///
/// `DefaultAuthRecoveryPolicy` is what ships: every request through `AuthenticatedTransport` is asked
/// through this, so the default is a production participant rather than a placeholder.
///
/// **Substituting one is not reachable from a capability target yet.** `PayabliSession` builds the
/// transport with the default and takes no policy, so only this module's tests supply another. The route
/// that needs a different answer is card-present device attestation, which is valid only for the exact
/// credential that obtained it, and refusing recovery there is a per-request property read above this
/// policy rather than a policy of its own. That work brings the injection path with it.
///
/// What the seam settles now is that the transport asks rather than re-deriving the status itself, which
/// is what keeps widening the refresh from also widening the replay: `AuthenticatedTransport` decides the
/// replay separately and for a different reason.
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
