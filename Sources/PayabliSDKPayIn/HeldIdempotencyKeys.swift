import Foundation
import PayabliSDKCore

/// What a held key belongs to.
///
/// A capture and an authorization hold one per payment reference; a capture of an authorization and a reversal hold
/// one per transaction they name.
enum HeldKeyScope: Hashable {
    case capture(reference: String)
    case authorize(reference: String)
    case captureAuthorized(transId: String)
    case void(transId: String)
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
        /// When the held key's record was last stamped, for a key sent again; nil for a new key.
        let heldSince: ContinuousClock.Instant?
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
    /// - Parameter claimsHeld: whether the attempt takes the key held for its scope.
    /// - Parameter payment: the payment the attempt is for, which must match the held key's to take it.
    /// - Parameter now: the moment the key is chosen.
    /// - Parameter mint: makes a new key.
    /// - Returns: the reservation to send under and to settle afterwards.
    /// - Throws: ``PayabliErrorType/retryNotSamePayment`` when the held key was made for another payment, and
    ///   ``PayabliErrorType/paymentReferenceOpen`` when a new payment names a reference whose key is still held.
    mutating func reserve(
        scope: HeldKeyScope,
        claimsHeld: Bool,
        payment: HeldPaymentDescription? = nil,
        now: ContinuousClock.Instant,
        mint: () -> String
    ) throws -> Reservation {
        sweep(now: now)
        if !claimsHeld, records[scope] != nil {
            throw PayabliGenericError(type: .paymentReferenceOpen, reason: "Payment reference still unresolved")
        }
        if claimsHeld, let held = records[scope] {
            if let heldPayment = held.payment, let payment, !heldPayment.isRepeated(by: payment) {
                throw PayabliGenericError(type: .retryNotSamePayment, reason: "Retry describes a different payment")
            }
            // The first description stays with the key, even if the record ages out while this send is in flight.
            return Reservation(
                scope: scope, key: held.key, reused: true, reservedAt: now, heldSince: held.reservedAt,
                payment: held.payment ?? payment
            )
        }
        return Reservation(scope: scope, key: mint(), reused: false, reservedAt: now, heldSince: nil, payment: payment)
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
        case .notAnswered, .repeatRefused:
            keep(reservation)
            return false
        case .answered:
            if records[scope]?.key == reservation.key {
                records[scope] = nil
            }
            return false
        case .unknown:
            return hold(reservation, now: now)
        }
    }

    /// Keeps a resent key on its earlier time, putting it back if it aged out while the send ran.
    ///
    /// - Parameter reservation: the reservation the attempt was sent under.
    private mutating func keep(_ reservation: Reservation) {
        guard let heldSince = reservation.heldSince, records[reservation.scope] == nil,
              records.count < Self.capacity
        else { return }
        // Its earlier time stays, so the next sweep removes it.
        records[reservation.scope] = Record(key: reservation.key, reservedAt: heldSince, payment: reservation.payment)
    }

    /// Holds the key of an attempt whose outcome is unknown, from that attempt's reservation.
    ///
    /// A scope holds one key, and a different key never displaces it.
    private mutating func hold(_ reservation: Reservation, now: ContinuousClock.Instant) -> Bool {
        // A key that expired during the send protects nothing, so it gives up its place before the cap is checked.
        sweep(now: now)
        let scope = reservation.scope
        if var existing = records[scope] {
            if existing.key == reservation.key {
                // This send may be the first to reach the service, so the key's age restarts from it.
                existing.reservedAt = max(existing.reservedAt, reservation.reservedAt)
                records[scope] = existing
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
