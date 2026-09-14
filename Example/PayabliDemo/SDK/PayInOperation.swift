/// What a form is for.
///
/// Its own file because two things read it: the form setup that carries it, and the
/// failure adapter, which classifies a conflict only on a flow that sends a key.
enum PayInOperation {
    /// Store an instrument for later. Sends no idempotency key.
    case storedMethod

    /// Take a payment now, under a key that makes a resubmission a retry.
    case capture

    /// Reverse a payment already taken. The SDK supplies the key; nothing here holds one.
    case void

    /// Whether the operation reaches the service under an idempotency key, which is what
    /// makes a conflict a repeat rather than the service's own answer.
    var sendsIdempotencyKey: Bool {
        switch self {
        case .storedMethod:
            false
        case .capture, .void:
            true
        }
    }
}
