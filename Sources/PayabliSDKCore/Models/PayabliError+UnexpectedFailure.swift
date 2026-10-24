/// The failure a public entry point reports for an error it does not know, or nil where the error
/// passes through unchanged.
///
/// A cancellation is the caller's own state and an error the SDK has already classified carries its
/// own type; both pass through. Anything else becomes the catalog's unknown failure: the failing
/// type's name rides a redacted cause, and the message never crosses, because a host-thrown error
/// can quote a rejected body or name the host's endpoint.
///
/// The boundary is the thrown error: a fatal error, a force-unwrap, an out-of-bounds read and an
/// overflow each end the process before an entry point can catch them.
extension Error {
    package var payabliUnexpectedFailure: PayabliGenericError? {
        if self is CancellationError || self is any PayabliError { return nil }
        return PayabliGenericError(
            type: .unknown,
            reason: PayabliErrorType.unknown.message,
            underlying: RedactedCause(self)
        )
    }
}
