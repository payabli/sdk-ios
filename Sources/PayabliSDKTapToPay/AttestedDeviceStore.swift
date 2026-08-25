import Foundation
import PayabliSDKCore

/// Reads and writes the device's bindings as one stored item.
///
/// One item, because two were two writes with a window between them: a crash in
/// the gap left half an identity behind, and half an identity read as a whole one.
///
/// A read that cannot be decoded is a read that answers nothing, and the item is
/// removed on the way out. Whatever wrote it is not this version, and a device
/// that re-enrolls once is cheaper than one that trusts a shape it cannot parse.
///
/// **A store that could not be read is not a store holding nothing.** Every read
/// below raises for the first and answers empty for the second, because a mutation
/// starts from what it read: an operational failure taken as empty writes back a
/// list with one binding in it and drops every other paypoint's.
///
/// Every mutation holds the lock across its read and its write. Unlocked, two
/// enrolments for different paypoints read the same list and the second write drops
/// the first binding, costing an enrolment for a paypoint with a key that works.
final class AttestedDeviceStore {
    private let storage: SecureStorage
    private let logger = PayabliLogger(category: .taptopay)

    /// One lock for every store in the process, not one per store.
    ///
    /// A facade builds its own service and its own store, and a host that talks to
    /// two paypoints builds two facades, so a per-store lock leaves exactly the
    /// case these bindings exist for unguarded: both stores read the same list from
    /// the same Keychain namespace and the second write drops the first binding.
    ///
    /// Broader than the namespace it protects, and that costs nothing: what it
    /// serializes is a Keychain read and write measured in microseconds.
    ///
    /// Two processes are outside it. Nothing in this SDK produces that, and the
    /// Keychain offers no compare-and-swap to build on.
    private static let lock = NSLock()

    init(storage: SecureStorage) {
        self.storage = storage
        discardSuperseded()
    }

    /// The two items an install from before the bindings item may hold. Neither
    /// records the paypoint it was issued for, so neither can be adopted: a handle
    /// presented to the wrong paypoint is refused, and the refusal retires a
    /// device that was still active. The device enrolls once instead.
    ///
    /// Never fails the caller. These are items nothing reads, so a store that
    /// cannot be reached leaves them for the next one rather than refusing to build
    /// a store at all.
    private func discardSuperseded() {
        for key in PayabliKeychainKey.superseded {
            guard let read = try? storage.string(forKey: key), read != nil else { continue }
            logger.info("[attest] discarding an identity stored without its paypoint")
            try? storage.remove(forKey: key)
        }
    }

    /// The binding for this entry point, moved to the front when it was not
    /// already there.
    ///
    /// Reading is what makes a binding recent, so the order is the order they were
    /// last used and the one that falls off the back is the coldest. Promoting on
    /// a write alone would order them by enrolment instead, and evict a binding
    /// that every session uses in favour of one that enrolled later.
    func binding(for entry: String) throws -> AttestedDevice? {
        try Self.lock.withLock {
            let held = try load()
            guard let record = held.binding(for: entry) else { return nil }
            if held.bindings.first != record {
                // The order decides only which binding is discarded first when the
                // store is full, so losing this write costs a worse choice of which
                // to drop and the next enrolment repairs it. Raising would turn a
                // read that already has its answer into a cold start.
                try? write(held.with(record))
            }
            return record
        }
    }

    func bindings() throws -> DeviceBindings {
        try Self.lock.withLock { try load() }
    }

    /// Adds or replaces this record's binding, leaving every other one alone.
    ///
    /// Throws when the write fails. Nothing here keeps an in-memory copy, so
    /// swallowing it would leave the service enrolled and this device holding
    /// nothing: the next request reloads an empty store and fails for a missing
    /// binding, and a device awaiting activation cannot activate at all.
    func remember(_ record: AttestedDevice) throws {
        try Self.lock.withLock {
            try write(load().with(record))
        }
    }

    /// Drops this entry point's binding.
    ///
    /// Throws when the rewrite fails, so a caller is never told a binding was
    /// dropped while it is still readable. A binding that outlives its own removal
    /// sends the same refused handle on the next warm start.
    func forget(entry: String) throws {
        try Self.lock.withLock {
            try write(load().without(entry: entry))
        }
    }

    /// Drops this entry point's binding only while it is still the one given.
    ///
    /// For a caller that read a binding, went away to ask about it, and came back
    /// with an answer. What it holds is what it asked about, and the entry point may
    /// hold something else by now: a newly attested binding written while the answer
    /// was on its way. Removing by entry point alone would drop that one on the
    /// strength of a question nobody asked about it.
    ///
    /// Answers whether it dropped anything, so the caller can say what happened.
    @discardableResult
    func forget(entry: String, ifStill record: AttestedDevice) throws -> Bool {
        try Self.lock.withLock {
            let held = try load()
            guard held.binding(for: entry) == record else { return false }
            try write(held.without(entry: entry))
            return true
        }
    }

    /// Drops this entry point's binding and its pending key together.
    ///
    /// One turn of the lock, because the two are one decision: this paypoint is
    /// being started over. Taken separately the lock is released between them, and
    /// an attestation that mints a key in that window has it deleted by the second
    /// half of a clear that was never about it. Its retry then mints another key
    /// and registers another device, which is the outcome the pending slot exists
    /// to prevent.
    func forgetEverything(for entry: String) throws {
        try Self.lock.withLock {
            try write(load().without(entry: entry))

            var pending = try loadPending()
            guard pending.removeValue(forKey: entry) != nil else { return }
            try writePending(pending)
        }
    }

    // MARK: - Keys an attestation is part way through

    /// The key this entry point minted and has not finished attesting.
    func pendingKey(for entry: String) throws -> String? {
        try Self.lock.withLock { try loadPending()[entry] }
    }

    /// Kept per entry point. A key can be attested once, so one entry point's key
    /// is no use to another, and a single slot let whichever started second
    /// overwrite the first: its owner's retry then minted another key and
    /// registered another device.
    func rememberPendingKey(_ keyId: String, for entry: String) throws {
        try Self.lock.withLock {
            var pending = try loadPending()
            pending[entry] = keyId
            try writePending(pending)
        }
    }

    /// Only this entry point's. Removing every one takes away a retry another
    /// paypoint is part way through.
    ///
    /// Throws, because the caller drops the pending slot immediately before burning
    /// the key it names, and the key can be attested only once. A removal reported
    /// as done while the record survives leaves the next attempt reusing a spent
    /// key, which is refused every time it is tried.
    func forgetPendingKey(for entry: String) throws {
        try Self.lock.withLock {
            var pending = try loadPending()
            guard pending.removeValue(forKey: entry) != nil else { return }
            try writePending(pending)
        }
    }

    private func loadPending() throws -> [String: String] {
        guard let raw = try storage.string(forKey: PayabliKeychainKey.pendingKeyId) else {
            return [:]
        }
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            logger.info("[attest] stored pending keys could not be decoded; discarding")
            try? storage.remove(forKey: PayabliKeychainKey.pendingKeyId)
            return [:]
        }
        return decoded
    }

    private func writePending(_ pending: [String: String]) throws {
        guard !pending.isEmpty else {
            try storage.remove(forKey: PayabliKeychainKey.pendingKeyId)
            return
        }
        guard let data = try? JSONEncoder().encode(pending),
              let raw = String(bytes: data, encoding: .utf8)
        else {
            throw PayabliTTPError.attestationFailed(reason: "The pending key could not be encoded")
        }
        try storage.set(raw, forKey: PayabliKeychainKey.pendingKeyId)
    }

    // MARK: - Under the lock

    /// Everything stored, empty when there is nothing to read, and a raise when the
    /// store could not answer.
    ///
    /// A record that will not decode is gone, so it answers empty and the item goes
    /// with it. The removal is best effort: the record is already dead, and raising
    /// here would strand the item, because a read that raises never reaches the
    /// removal on the next attempt either.
    private func load() throws -> DeviceBindings {
        guard let raw = try storage.string(forKey: PayabliKeychainKey.deviceBindings) else {
            return DeviceBindings()
        }
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DeviceBindings.self, from: data)
        else {
            logger.info("[attest] stored bindings could not be decoded; discarding")
            try? storage.remove(forKey: PayabliKeychainKey.deviceBindings)
            return DeviceBindings()
        }
        return decoded
    }

    private func write(_ bindings: DeviceBindings) throws {
        guard !bindings.bindings.isEmpty else {
            try storage.remove(forKey: PayabliKeychainKey.deviceBindings)
            return
        }
        guard let data = try? JSONEncoder().encode(bindings),
              let raw = String(bytes: data, encoding: .utf8)
        else {
            throw PayabliTTPError.attestationFailed(reason: "The device binding could not be encoded")
        }
        try storage.set(raw, forKey: PayabliKeychainKey.deviceBindings)
    }
}
