/// What a form is for.
///
/// Its own file because two things read it: the form setup that carries it, and the
/// failure adapter, which classifies a conflict only on the flow that sends a key.
enum PayInOperation {
    /// Store an instrument for later. Sends no idempotency key.
    case storedMethod

    /// Take a payment now, under a key that makes a resubmission a retry.
    case capture
}
