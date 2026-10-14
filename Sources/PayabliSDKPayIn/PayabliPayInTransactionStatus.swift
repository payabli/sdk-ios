/// Where a transaction stands, as the service recorded it.
///
/// `captured`, `declined`, `voided` and `returned` are settled. `initiated`, `authorized` and `failed` are not
/// final.
public enum PayabliPayInTransactionStatus: Sendable, Hashable {
    case initiated
    case authorized
    case captured
    case declined
    case voided
    case returned
    case failed
    /// A status this SDK does not name, carrying the service's number for it.
    case other(Int)

    /// Reads the service's status number. Each number is listed, so an unlisted one is ``other(_:)``.
    init(wire: Int) {
        switch wire {
        case 10: self = .initiated
        case 11: self = .authorized
        case 1: self = .captured
        case 2, 3: self = .declined
        case 5: self = .voided
        case -2: self = .returned
        case -1, 0: self = .failed
        default: self = .other(wire)
        }
    }
}
