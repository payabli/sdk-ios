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
/// Every mutation holds the lock across its read and its write. Unlocked, two
/// enrolments for different paypoints read the same list and the second write drops
/// the first binding, costing an enrolment for a paypoint with a key that works.
/// The lock is per store and one store is built per service, so two services
/// sharing the Keychain namespace still race, which is why the facade builds one.
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
    private static let lock = NSLock()

    init(storage: SecureStorage) {
        self.storage = storage
        discardSuperseded()
    }

    /// The two items an install from before the bindings item may hold. Neither
    /// records the paypoint it was issued for, so neither can be adopted: a handle
    /// presented to the wrong paypoint is refused, and the refusal retires a
    /// device that was still active. The device enrolls once instead.
    private func discardSuperseded() {
        for key in PayabliKeychainKey.superseded where storage.string(forKey: key) != nil {
            logger.info("[attest] discarding an identity stored without its paypoint")
            storage.remove(forKey: key)
        }
    }

    /// The binding for this entry point, moved to the front when it was not
    /// already there.
    ///
    /// Reading is what makes a binding recent, so the order is the order they were
    /// last used and the one that falls off the back is the coldest. Promoting on
    /// a write alone would order them by enrolment instead, and evict a binding
    /// that every session uses in favour of one that enrolled later.
    func binding(for entry: String) -> AttestedDevice? {
        Self.lock.withLock {
            let held = load()
            guard let record = held.binding(for: entry) else { return nil }
            if held.bindings.first != record {
                try? write(held.with(record))
            }
            return record
        }
    }

    func bindings() -> DeviceBindings {
        Self.lock.withLock { load() }
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

    func forget(entry: String) {
        Self.lock.withLock {
            let remaining = load().without(entry: entry)
            do {
                try write(remaining)
            } catch {
                logger.info("[attest] the binding could not be dropped")
            }
        }
    }

    // MARK: - Keys an attestation is part way through

    /// The key this entry point minted and has not finished attesting.
    func pendingKey(for entry: String) -> String? {
        Self.lock.withLock { loadPending()[entry] }
    }

    /// Kept per entry point. A key can be attested once, so one entry point's key
    /// is no use to another, and a single slot let whichever started second
    /// overwrite the first: its owner's retry then minted another key and
    /// registered another device.
    func rememberPendingKey(_ keyId: String, for entry: String) throws {
        try Self.lock.withLock {
            var pending = loadPending()
            pending[entry] = keyId
            try writePending(pending)
        }
    }

    /// Only this entry point's. Removing every one takes away a retry another
    /// paypoint is part way through.
    func forgetPendingKey(for entry: String) {
        Self.lock.withLock {
            var pending = loadPending()
            guard pending.removeValue(forKey: entry) != nil else { return }
            try? writePending(pending)
        }
    }

    private func loadPending() -> [String: String] {
        guard let raw = storage.string(forKey: PayabliKeychainKey.pendingKeyId),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func writePending(_ pending: [String: String]) throws {
        guard !pending.isEmpty else {
            storage.remove(forKey: PayabliKeychainKey.pendingKeyId)
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

    private func load() -> DeviceBindings {
        guard let raw = storage.string(forKey: PayabliKeychainKey.deviceBindings) else {
            return DeviceBindings()
        }
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DeviceBindings.self, from: data)
        else {
            logger.info("[attest] stored bindings could not be decoded; discarding")
            storage.remove(forKey: PayabliKeychainKey.deviceBindings)
            return DeviceBindings()
        }
        return decoded
    }

    private func write(_ bindings: DeviceBindings) throws {
        guard let data = try? JSONEncoder().encode(bindings),
              let raw = String(bytes: data, encoding: .utf8)
        else {
            throw PayabliTTPError.attestationFailed(reason: "The device binding could not be encoded")
        }
        try storage.set(raw, forKey: PayabliKeychainKey.deviceBindings)
    }
}
