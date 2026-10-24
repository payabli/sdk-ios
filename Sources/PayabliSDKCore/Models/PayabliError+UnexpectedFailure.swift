/// The SDK's unknown failure for an error a public entry point does not know, or nil for a
/// cancellation or an error the SDK has already classified. The failing type's name rides a
/// redacted cause and its message never crosses; a trap ends the process before any catch.
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
