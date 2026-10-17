import Foundation
import PayabliSDKCore

/// What a held key belongs to.
///
/// A capture and an authorization hold the key of the most recent attempt on that route whose outcome is unknown.
/// A capture of an authorization and a reversal hold one per transaction they name.
enum HeldKeyScope: Hashable {
    case capture
    case authorize
    case captureAuthorized(transId: String)
    case void(transId: String)

    /// Whether the scope names the transaction it acts on, so any answer about that transaction settles it.
    var namesTransaction: Bool {
        switch self {
        case .capture, .authorize: false
        case .captureAuthorized, .void: true
        }
    }
}

/// The keys of attempts whose outcome nobody knows, kept so a repeat can be refused rather than taken again.
///
/// In memory, for one flow. A key ages out once the service would no longer recognise it, counted from the latest
/// send that may have reached it.
struct HeldIdempotencyKeys {
    /// How many attempts may be held at once. Past it a new attempt still sends a key and is not held.
    static let capacity = 16

    /// The key one attempt sends, and where it came from.
    struct Reservation: Equatable {
        let scope: HeldKeyScope
        let key: String
        /// The key was held for an earlier attempt and is being sent again.
        let reused: Bool
        let reservedAt: ContinuousClock.Instant
        /// The payment the key was made for, which stays the same each time a held key is sent.
        let payment: HeldPaymentDescription?
    }

    /// What became of an attempt, as far as its key is concerned.
    enum Outcome: Equatable {
        /// The service answered about the payment: it succeeded, was declined, or was refused as invalid.
        case answered
        /// The request may have been carried out and nobody knows whether it was.
        case unknown
        /// The service refused a held key it had already seen, so the earlier attempt reached it.
        case repeatRefused
        /// Nothing answered about the payment: the request never left, or was refused before it was read.
        case notAnswered
    }

    private struct Record {
        var key: String
        var reservedAt: ContinuousClock.Instant
        let payment: HeldPaymentDescription?
    }

    private let maxAge: Duration
    private var records: [HeldKeyScope: Record] = [:]

    /// Whether the last attempt that should have been held found no room. Reported once until a key is held again.
    private(set) var isSaturated = false

    init(maxAge: Duration = payabliIdempotencyKeyMaxAge) {
        self.maxAge = maxAge
    }

    /// The key an attempt sends.
    ///
    /// - Parameter scope: what the attempt belongs to.
    /// - Parameter supplied: the caller's own key, which is sent whenever it is set.
    /// - Parameter claimsHeld: whether the attempt takes the key held for its scope.
    /// - Parameter payment: the payment the attempt is for, which must match the held key's to take it.
    /// - Parameter now: the moment the key is chosen.
    /// - Parameter mint: makes a new key.
    /// - Returns: the reservation to send under and to settle afterwards.
    /// - Throws: ``PayabliErrorType/retryNotSamePayment`` when the held key was made for another payment.
    mutating func reserve(
        scope: HeldKeyScope,
        supplied: String?,
        claimsHeld: Bool,
        payment: HeldPaymentDescription? = nil,
        now: ContinuousClock.Instant,
        mint: () -> String
    ) throws -> Reservation {
        sweep(now: now)
        if let supplied {
            let key = supplied.payabliCaptureTrimmed
            return Reservation(scope: scope, key: key, reused: false, reservedAt: now, payment: payment)
        }
        if claimsHeld, let held = records[scope] {
            if let heldPayment = held.payment, let payment, !heldPayment.isRepeated(by: payment) {
                throw PayabliGenericError(type: .retryNotSamePayment, reason: "Retry describes a different payment")
            }
            // The first description stays with the key, even if the record ages out while this send is in flight.
            return Reservation(
                scope: scope, key: held.key, reused: true, reservedAt: now, payment: held.payment ?? payment
            )
        }
        return Reservation(scope: scope, key: mint(), reused: false, reservedAt: now, payment: payment)
    }

    /// Records what became of an attempt.
    ///
    /// - Parameter reservation: the reservation the attempt was sent under.
    /// - Parameter outcome: what became of it.
    /// - Parameter now: the moment it ended, against which expired keys are dropped before one is held.
    /// - Returns: whether the attempt should have been held and found no room, for the first time since a key was
    ///   last held.
    @discardableResult
    mutating func settle(_ reservation: Reservation, outcome: Outcome, now: ContinuousClock.Instant) -> Bool {
        let scope = reservation.scope
        switch outcome {
        case .notAnswered:
            return false
        case .answered:
            if scope.namesTransaction || records[scope]?.key == reservation.key {
                records[scope] = nil
            }
            return false
        case .repeatRefused:
            // The service already held the key from an earlier send, so this one restarts nothing.
            return false
        case .unknown:
            return hold(reservation, now: now)
        }
    }

    /// Holds the key of an attempt whose outcome is unknown, from that attempt's reservation.
    ///
    /// A transaction's record is never displaced by a different key; a route's is, since a retry claims the latest.
    private mutating func hold(_ reservation: Reservation, now: ContinuousClock.Instant) -> Bool {
        // A key that expired during the send protects nothing, so it gives up its place before the cap is checked.
        sweep(now: now)
        let scope = reservation.scope
        if var existing = records[scope] {
            if existing.key == reservation.key {
                // This send may be the first to reach the service, so the key's age restarts from it.
                existing.reservedAt = max(existing.reservedAt, reservation.reservedAt)
                records[scope] = existing
            } else if !scope.namesTransaction {
                records[scope] = Record(key: reservation.key, reservedAt: reservation.reservedAt, payment: reservation.payment)
            }
            isSaturated = false
            return false
        }
        guard records.count < Self.capacity else {
            defer { isSaturated = true }
            return !isSaturated
        }
        records[scope] = Record(key: reservation.key, reservedAt: reservation.reservedAt, payment: reservation.payment)
        isSaturated = false
        return false
    }

    /// Drops every key the service would no longer recognise.
    private mutating func sweep(now: ContinuousClock.Instant) {
        records = records.filter { _, record in
            record.reservedAt.duration(to: now) < maxAge
        }
    }
}
