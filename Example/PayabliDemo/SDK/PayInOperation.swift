/// What a form is for.
///
/// Its own file because two things read it: the form setup that carries it, and the
/// failure adapter, which classifies a conflict only on a flow that can send one key twice.
enum PayInOperation {
    /// Store an instrument for later. Sends no idempotency key.
    case storedMethod

    /// Take a payment now, under a key that makes a resubmission a retry.
    case capture

    /// Reverse a payment already taken. The SDK mints the key and never shows it.
    case void

    /// Whether the same key can reach the service twice, which is what makes a conflict a repeat.
    ///
    /// Only the form-driven capture can: its key rides on the request configuration and stays put
    /// until a new attempt is drawn, so submitting again sends the one the service already holds. A
    /// reversal takes no key and the SDK mints a fresh one per call, so it can never send a repeat.
    var canRepeatUnderOneKey: Bool {
        switch self {
        case .storedMethod, .void:
            false
        case .capture:
            true
        }
    }
}
