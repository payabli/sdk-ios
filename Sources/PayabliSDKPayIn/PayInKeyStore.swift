import Foundation
import PayabliSDKCore

/// The recorded keys of every flow in this process, one table per entry point and environment, so a rebuilt flow
/// resends what the last one sent. Each key ages out on ``payabliIdempotencyKeyMaxAge`` once no send of it is under way.
final class PayInKeyStore: @unchecked Sendable {
    /// The store every flow in this process uses.
    static let process = PayInKeyStore()

    /// An entry point, as it is sent, and an environment.
    private struct Partition: Hashable {
        let entry: String
        let environment: String

        init(_ entry: String, _ environment: PayabliEnvironment) {
            self.entry = entry.payabliCaptureTrimmed
            self.environment = environment.name
        }
    }

    private let lock = NSLock()
    private var partitions: [Partition: HeldIdempotencyKeys] = [:]

    /// The key an attempt sends. Reading and recording are one operation under one lock, so below the capacity two
    /// flows sending one payment at once cannot each find nothing and make a key.
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
            let partition = Partition(entry, environment)
            var keys = partitions[partition] ?? HeldIdempotencyKeys()
            let reservation = try keys.reserve(
                scope: scope, claimsHeld: claimsHeld, payment: payment, now: now, mint: mint
            )
            partitions[partition] = keys.isIdle ? nil : keys
            return reservation
        }
    }

    /// Ends a send, as ``HeldIdempotencyKeys/settle(_:outcome:)`` does.
    ///
    /// - Parameter entry: the entry point the attempt was sent to.
    /// - Parameter environment: the environment the attempt was sent to.
    /// - Parameter reservation: the reservation the attempt was sent under.
    /// - Parameter outcome: what became of it.
    func settle(
        entry: String,
        environment: PayabliEnvironment,
        _ reservation: HeldIdempotencyKeys.Reservation,
        outcome: HeldIdempotencyKeys.Outcome
    ) {
        lock.withLock {
            let partition = Partition(entry, environment)
            guard var keys = partitions[partition] else { return }
            keys.settle(reservation, outcome: outcome)
            partitions[partition] = keys.isIdle ? nil : keys
        }
    }

    /// Drops every recorded key. Process state for tests.
    func forgetHeld() {
        lock.withLock { partitions.removeAll() }
    }

    /// Drops every key the service would no longer recognise and no send is using, for every entry point and
    /// environment, and every table left empty. Called with the lock held.
    ///
    /// - Parameter now: the moment a key's age is read against.
    private func sweep(now: ContinuousClock.Instant) {
        for (partition, var keys) in partitions {
            keys.sweep(now: now)
            partitions[partition] = keys.isIdle ? nil : keys
        }
    }
}
