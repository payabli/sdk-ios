import Foundation
import PayabliSDKCore

/// The held keys of every flow in this process, one table per entry point and environment, so a rebuilt flow
/// resends what the last one held. Each key ages out on ``payabliIdempotencyKeyMaxAge``.
final class PayInKeyStore: @unchecked Sendable {
    /// The store every flow in this process uses.
    static let process = PayInKeyStore()

    private struct Partition: Hashable {
        let entry: String
        let environment: String
    }

    private let lock = NSLock()
    private var partitions: [Partition: HeldIdempotencyKeys] = [:]

    /// The key an attempt sends.
    ///
    /// - Parameter entry: the entry point the attempt is sent to.
    /// - Parameter environment: the environment the attempt is sent to.
    /// - Parameter scope: what the attempt belongs to.
    /// - Parameter claimsHeld: whether the attempt takes the key held for its scope.
    /// - Parameter payment: the payment the attempt is for, which must match the held key's to take it.
    /// - Parameter now: the moment the key is chosen.
    /// - Parameter mint: makes a new key.
    /// - Returns: the reservation to send under and to settle afterwards.
    /// - Throws: what ``HeldIdempotencyKeys/reserve(scope:claimsHeld:payment:now:mint:)`` throws.
    func reserve(
        entry: String,
        environment: PayabliEnvironment,
        scope: HeldKeyScope,
        claimsHeld: Bool,
        payment: HeldPaymentDescription?,
        now: ContinuousClock.Instant,
        mint: () -> String
    ) throws -> HeldIdempotencyKeys.Reservation {
        try lock.withLock {
            sweep(now: now)
            var keys = partitions[Partition(entry: entry, environment: environment.name)] ?? HeldIdempotencyKeys()
            return try keys.reserve(scope: scope, claimsHeld: claimsHeld, payment: payment, now: now, mint: mint)
        }
    }

    /// Records what became of an attempt.
    ///
    /// - Parameter entry: the entry point the attempt was sent to.
    /// - Parameter environment: the environment the attempt was sent to.
    /// - Parameter reservation: the reservation the attempt was sent under.
    /// - Parameter outcome: what became of it.
    /// - Parameter now: the moment it ended.
    /// - Returns: whether the attempt should have been held and found no room, for the first time since a key was
    ///   last held for this entry point and environment.
    @discardableResult
    func settle(
        entry: String,
        environment: PayabliEnvironment,
        _ reservation: HeldIdempotencyKeys.Reservation,
        outcome: HeldIdempotencyKeys.Outcome,
        now: ContinuousClock.Instant
    ) -> Bool {
        lock.withLock {
            sweep(now: now)
            let partition = Partition(entry: entry, environment: environment.name)
            var keys = partitions[partition] ?? HeldIdempotencyKeys()
            let full = keys.settle(reservation, outcome: outcome, now: now)
            partitions[partition] = keys.isIdle ? nil : keys
            return full
        }
    }

    /// Drops every held key. Process state for tests.
    func forgetHeld() {
        lock.withLock { partitions.removeAll() }
    }

    /// Drops every key the service would no longer recognise, for every entry point and environment, and every table
    /// left idle.
    /// Called with the lock held.
    ///
    /// - Parameter now: the moment a key's age is read against.
    private func sweep(now: ContinuousClock.Instant) {
        for (partition, var keys) in partitions {
            keys.sweep(now: now)
            partitions[partition] = keys.isIdle ? nil : keys
        }
    }
}
