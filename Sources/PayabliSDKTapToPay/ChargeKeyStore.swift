import Foundation
import PayabliSDKCore

/// The idempotency keys of unsettled charges, in memory only, newest first per entry point and environment. A declared
/// retry is handed the newest, never while a send of it is under way, and every key ages out on
/// ``payabliIdempotencyKeyMaxAge``, as the service forgets it. Every terminal shares ``process``, so a second terminal's
/// retry repeats the first one's charge.
package final class ChargeKeyStore: @unchecked Sendable {
    /// The store every terminal in this process uses.
    package static let process = ChargeKeyStore()

    /// How many entry points may hold unsettled charges at once. Nothing is evicted to make room: each key is the
    /// only thing that would recognise its charge's repeat, and every key ages out on its own.
    static let capacity = 4

    private let newKey: @Sendable () -> String
    private let now: @Sendable () -> ContinuousClock.Instant
    private let lock = NSLock()
    private var held: [ChargeAttempt] = []

    /// - Parameter newKey: mints a key for a charge that holds none.
    /// - Parameter now: the monotonic clock every stamp is read from.
    package init(
        newKey: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.newKey = newKey
        self.now = now
    }

    /// The key a charge's opening sends. A `.retry` is handed the newest key held for `entry` under `environment` and
    /// mints only when none is held; a `.newPayment` always mints and leaves every held key where it is.
    ///
    /// - Parameter entry: the entry point the charge is for.
    /// - Parameter environment: the environment the charge is sent to.
    /// - Parameter attempt: whether the host declared the charge a retry.
    /// - Parameter description: the payment the charge describes.
    /// - Returns: the key to send, whether it was already held, and when this send reserved it.
    /// - Throws: ``TapToPayError`` of type `paymentReferenceOpen` when a retry finds the held key's send under way, and
    ///   of type `retryNotSamePayment` when it describes another payment than the held key's; either way the key stays
    ///   held. Of type `tooManyOpenCharges` when every slot holds another entry point's charge.
    func reserve(
        entry: String,
        environment: PayabliEnvironment,
        attempt: PayabliAttempt,
        description: ChargeDescription
    ) throws -> Reservation {
        try lock.withLock {
            let now = now()
            sweep(now)
            if attempt == .retry, let existing = held.first(where: { $0.matches(entry, environment) }) {
                guard !existing.underWay else {
                    throw Self.refusal(.paymentReferenceOpen)
                }
                guard existing.payment.isRepeated(by: description) else {
                    throw Self.refusal(.retryNotSamePayment)
                }
                existing.underWay = true
                return Reservation(key: existing.key, reused: true, reservedAt: now)
            }
            var slots: [String] = []
            for attempt in held where !slots.contains(attempt.slot) {
                slots.append(attempt.slot)
            }
            let slot = ChargeAttempt.slot(entry, environment)
            if !slots.contains(slot), slots.count >= Self.capacity {
                throw Self.refusal(.tooManyOpenCharges)
            }
            let minted = ChargeAttempt(
                entry: entry,
                environment: environment.name,
                key: newKey(),
                reservedAt: now,
                payment: description
            )
            minted.underWay = true
            held.insert(minted, at: 0)
            return Reservation(key: minted.key, reused: false, reservedAt: now)
        }
    }

    /// Forgets `key` for `entry` under `environment`, because its charge reached an outcome not in doubt. A key no
    /// longer held is left alone.
    ///
    /// - Parameter entry: the entry point the charge was for.
    /// - Parameter environment: the environment the charge was sent to.
    /// - Parameter key: the key the charge sent.
    func settle(entry: String, environment: PayabliEnvironment, key: String) {
        lock.withLock {
            held.removeAll { $0.matches(entry, environment) && $0.key == key }
        }
    }

    /// Ends a send of `key`. A key still held drops every other key for `entry` under `environment`, since only the
    /// newest unresolved charge can be retried, and its clock restarts at `arrivedAt`; a settled key supersedes nothing.
    ///
    /// - Parameter entry: the entry point the charge was for.
    /// - Parameter environment: the environment the charge was sent to.
    /// - Parameter key: the key the send used.
    /// - Parameter arrivedAt: when the send that may have reached the service was reserved, or `nil` when it cannot
    ///   have written the service's marker.
    func supersede(entry: String, environment: PayabliEnvironment, key: String, arrivedAt: ContinuousClock.Instant?) {
        lock.withLock {
            guard let kept = held.first(where: { $0.matches(entry, environment) && $0.key == key }) else { return }
            kept.underWay = false
            held.removeAll { $0.matches(entry, environment) && $0.key != key }
            if let arrivedAt {
                kept.reservedAt = max(kept.reservedAt, arrivedAt)
            }
        }
    }

    /// The held keys as a retry describing `description` would find them, read without reserving anything.
    ///
    /// - Parameter entry: the entry point the retry is for.
    /// - Parameter environment: the environment the retry is sent to.
    /// - Parameter description: the payment the retry describes.
    /// - Returns: whether the key a retry is handed has a send under way, and whether the retry describes the payment
    ///   of any held key, not only the newest; `nil` when nothing is held.
    func heldRetry(entry: String, environment: PayabliEnvironment, description: ChargeDescription) -> HeldRetry? {
        lock.withLock {
            sweep(now())
            let keys = held.filter { $0.matches(entry, environment) }
            guard let newest = keys.first else { return nil }
            return HeldRetry(
                underWay: newest.underWay,
                describesHeld: keys.contains { $0.payment.isRepeated(by: description) }
            )
        }
    }

    /// Drops every key past the bound that no send is using. Called with the lock held.
    ///
    /// - Parameter now: the instant the bound is measured to.
    private func sweep(_ now: ContinuousClock.Instant) {
        held.removeAll { !$0.underWay && now - $0.reservedAt >= payabliIdempotencyKeyMaxAge }
    }

    private static func refusal(_ type: PayabliErrorType) -> TapToPayError {
        TapToPayError(type: type, reason: type.message, detail: nil)
    }
}

extension ChargeKeyStore {
    /// A reserved key, whether it was already held, and when this send reserved it. Its description names neither.
    struct Reservation: CustomStringConvertible {
        let key: String
        let reused: Bool
        let reservedAt: ContinuousClock.Instant

        var description: String {
            "Reservation(reused: \(reused))"
        }
    }

    /// The held keys as a retry finds them, read in one pass under the lock.
    struct HeldRetry {
        /// Whether the newest key, the one ``ChargeKeyStore/reserve(entry:environment:attempt:description:)`` would
        /// hand a retry, has a send under way.
        let underWay: Bool
        /// Whether the retry describes the payment of any held key.
        let describesHeld: Bool
    }
}

/// One entry point's charge under one environment, and the key its repeat carries. Its description names neither the
/// entry point nor the key.
private final class ChargeAttempt: CustomStringConvertible {
    let entry: String
    let environment: String
    let key: String
    let payment: ChargeDescription
    var reservedAt: ContinuousClock.Instant
    var underWay = false

    init(entry: String, environment: String, key: String, reservedAt: ContinuousClock.Instant, payment: ChargeDescription) {
        self.entry = entry
        self.environment = environment
        self.key = key
        self.reservedAt = reservedAt
        self.payment = payment
    }

    var description: String {
        "ChargeAttempt(underWay: \(underWay))"
    }

    var slot: String {
        Self.slot(entry, environment)
    }

    func matches(_ entry: String, _ environment: PayabliEnvironment) -> Bool {
        self.entry == entry && self.environment == environment.name
    }

    static func slot(_ entry: String, _ environment: PayabliEnvironment) -> String {
        slot(entry, environment.name)
    }

    static func slot(_ entry: String, _ environment: String) -> String {
        "\(environment)\u{0}\(entry)"
    }
}
