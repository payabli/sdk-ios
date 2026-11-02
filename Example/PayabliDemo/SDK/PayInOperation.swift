import PayabliSDKPayIn

/// What a form is for.
///
/// Its own file because two things read it: the form setup that carries it, and the
/// failure adapter, which classifies a conflict only on a flow that can send one key twice.
enum PayInOperation {
    /// Store an instrument for later. Sends no idempotency key.
    case storedMethod

    /// Take a payment now, under a key that makes a resubmission a retry.
    case capture

    /// Hold an amount on a card to capture later, under a key the same way.
    case authorize

    /// Reverse a payment already taken. The SDK mints the key and never shows it.
    case void

    /// Whether the same key can reach the service twice, which is what makes a conflict a repeat.
    ///
    /// A form's capture or authorization can: it keeps its payment until a new attempt is drawn. A reversal can't.
    var canRepeatUnderOneKey: Bool {
        switch self {
        case .storedMethod, .void:
            false
        case .capture, .authorize:
            true
        }
    }
}
