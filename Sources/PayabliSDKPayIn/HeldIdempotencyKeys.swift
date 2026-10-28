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

/// The key of every payment sent and not yet answered, for one entry point and environment, in ``PayInKeyStore``.
///
/// A key ages out once the service would no longer recognise it and no send of it is under way.
struct HeldIdempotencyKeys {
    /// How many payments may hold a key at once. Past it a new attempt still sends a key and it is not recorded.
    static let capacity = 16

    /// The key one attempt sends, and where it came from.
    struct Reservation: Equatable {
        let scope: HeldKeyScope
        let key: String
        /// The key was recorded for an earlier attempt and is being sent again.
        let reused: Bool
        let reservedAt: ContinuousClock.Instant
        /// The payment the key was made for, which stays the same each time a recorded key is sent.
        let payment: HeldPaymentDescription?
        /// The key should have been recorded and found no room, for the first time since a key was last recorded.
        let foundNoRoom: Bool
    }

    /// What became of an attempt, as far as its key is concerned.
    enum Outcome: Equatable {
        /// The service answered about the payment: it succeeded, was declined, or was refused as invalid.
        case answered
        /// The request may have been carried out and nobody knows whether it was.
        case unknown
        /// The service refused a recorded key it had already seen, so an earlier attempt reached it.
        case repeatRefused
        /// Nothing answered about the payment: the request never left, or was refused before it was read.
        case notAnswered
    }

    private struct Record {
        let key: String
        var reservedAt: ContinuousClock.Instant
        let payment: HeldPaymentDescription?
        /// Whether a send of this key has not yet ended, which refuses any other and keeps the key from the sweep.
        var sending: Bool
        /// Whether the service may know this key, which keeps it when no send of it is under way.
        var carried: Bool
    }

    private let maxAge: Duration
    private var records: [HeldKeyScope: Record] = [:]

    /// Whether the last attempt that should have been recorded found no room. Reported once until a key is recorded.
    private var isSaturated = false

    /// Whether nothing is recorded, so the table can be dropped.
    var isIdle: Bool {
        records.isEmpty
    }

    init(maxAge: Duration = payabliIdempotencyKeyMaxAge) {
        self.maxAge = maxAge
    }

    /// The key an attempt sends: the one recorded for its scope, otherwise a new one, recorded as it is made.
    ///
    /// - Parameter scope: what the attempt belongs to.
    /// - Parameter claimsHeld: whether the attempt takes the key recorded for its scope.
    /// - Parameter payment: the payment the attempt is for, which must match the recorded key's to take it.
    /// - Parameter now: the moment the key is chosen.
    /// - Parameter mint: makes a new key.
    /// - Returns: the reservation to send under and to settle afterwards.
    /// - Throws: ``PayabliErrorType/paymentReferenceOpen`` when a send of the recorded key is under way, or a new payment
    ///   names a reference whose key is recorded, and ``PayabliErrorType/retryNotSamePayment`` when the recorded key was
    ///   made for another payment.
    mutating func reserve(
        scope: HeldKeyScope,
        claimsHeld: Bool,
        payment: HeldPaymentDescription? = nil,
        now: ContinuousClock.Instant,
        mint: () -> String
    ) throws -> Reservation {
        sweep(now: now)
        if var held = records[scope] {
            guard claimsHeld, !held.sending else {
                throw PayabliGenericError(type: .paymentReferenceOpen, reason: "Payment reference still unresolved")
            }
            if let heldPayment = held.payment, let payment, !heldPayment.isRepeated(by: payment) {
                throw PayabliGenericError(type: .retryNotSamePayment, reason: "Retry describes a different payment")
            }
            held.sending = true
            records[scope] = held
            return Reservation(
                scope: scope, key: held.key, reused: true, reservedAt: now, payment: held.payment ?? payment,
                foundNoRoom: false
            )
        }
        let key = mint()
        guard records.count < Self.capacity else {
            defer { isSaturated = true }
            return Reservation(
                scope: scope, key: key, reused: false, reservedAt: now, payment: payment, foundNoRoom: !isSaturated
            )
        }
        records[scope] = Record(key: key, reservedAt: now, payment: payment, sending: true, carried: false)
        isSaturated = false
        return Reservation(scope: scope, key: key, reused: false, reservedAt: now, payment: payment, foundNoRoom: false)
    }

    /// Ends a send: an answer forgets its key, and any other ending keeps it only while a send of it may have reached
    /// the service. A key not recorded, past the capacity or already answered, is left alone.
    ///
    /// - Parameter reservation: the reservation the attempt was sent under.
    /// - Parameter outcome: what became of it.
    mutating func settle(_ reservation: Reservation, outcome: Outcome) {
        let scope = reservation.scope
        guard var held = records[scope], held.key == reservation.key else { return }
        held.sending = false
        switch outcome {
        case .answered:
            records[scope] = nil
            return
        case .unknown:
            held.carried = true
            held.reservedAt = max(held.reservedAt, reservation.reservedAt)
        case .repeatRefused:
            // The service has seen the key, so it was carried out; the clock it already had stands.
            held.carried = true
        case .notAnswered:
            if !held.carried {
                records[scope] = nil
                return
            }
        }
        records[scope] = held
    }

    /// Drops every key the service would no longer recognise, unless a send of it is under way.
    ///
    /// - Parameter now: the moment a key's age is read against.
    mutating func sweep(now: ContinuousClock.Instant) {
        records = records.filter { _, record in
            record.sending || record.reservedAt.duration(to: now) < maxAge
        }
    }
}
