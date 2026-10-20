/// Where a transaction stands, read from ``PayabliPayInTransaction/transStatus``, which keeps the number.
///
/// Each case names the status numbers it covers and whether the payment's outcome is known. Where it is not,
/// the status may still change, so read the transaction again before acting on it.
public enum PayabliPayInTransactionStatus: Sendable, Hashable {
    /// 10. Outcome not known.
    case initiated
    /// 11. Outcome not known.
    case authorized
    /// 1. Outcome known: paid, and still voidable until its batch closes.
    case captured
    /// 2 and 3. Outcome known: not paid.
    case declined
    /// 5. Outcome known: not paid.
    case voided
    /// -2. Outcome known: not paid, and no money moved.
    case blocked
    /// -1 and 0. Outcome not known.
    case failed
    /// Any other number, carried here. Outcome not known.
    case other(Int)

    /// Reads the status number. Each number is listed, so an unlisted one is ``other(_:)``.
    ///
    /// - Parameter wire: the status number, as ``PayabliPayInTransaction/transStatus`` carries it.
    init(wire: Int) {
        switch wire {
        case 10: self = .initiated
        case 11: self = .authorized
        case 1: self = .captured
        case 2, 3: self = .declined
        case 5: self = .voided
        case -2: self = .blocked
        case -1, 0: self = .failed
        default: self = .other(wire)
        }
    }
}
