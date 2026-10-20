import Foundation
import PayabliSDKCore

/// Reads and writes the device's bindings as one stored item.
///
/// A store that could not be read is not a store holding nothing: every read below
/// raises for the first and answers empty for the second, since a mutation starts
/// from what it read and would otherwise drop every other paypoint's binding. A
/// record that will not decode answers nothing and is removed.
///
/// Every mutation holds the lock across its read and its write.
final class AttestedDeviceStore {
    private let storage: SecureStorage
    private let logger = PayabliLogger(category: .taptopay)

    /// One lock for every store in the process: a facade builds its own store, so a
    /// host talking to two paypoints has two over the same Keychain namespace. Two
    /// processes are outside it, and the Keychain offers no compare-and-swap.
    private static let lock = NSLock()

    init(storage: SecureStorage) {
        self.storage = storage
        discardSuperseded()
    }

    /// The two items an install from before the bindings item may hold. Neither
    /// records the paypoint it was issued for, so neither can be adopted: presenting
    /// a handle to the wrong paypoint retires a device that was still active.
    ///
    /// Never fails the caller, since nothing reads these.
    private func discardSuperseded() {
        for key in PayabliKeychainKey.superseded {
            guard let read = try? storage.string(forKey: key), read != nil else { continue }
            logger.info("[attest] discarding an identity stored without its paypoint")
            try? storage.remove(forKey: key)
        }
    }

    /// The binding for this entry point, moved to the front when it was not already
    /// there: reading is what makes a binding recent, so the one that falls off the
    /// back is the coldest.
    ///
    /// - Parameter entry: the entry point whose held binding is asked for.
    /// - Returns: the entry point's binding, or `nil` where none is held.
    func binding(for entry: String) throws -> AttestedDevice? {
        try Self.lock.withLock {
            let held = try load()
            guard let record = held.binding(for: entry) else { return nil }
            if held.bindings.first != record {
                // Order decides only which binding is discarded first, and the
                // next enrolment repairs a lost write.
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
    /// Throws when the write fails: nothing here keeps an in-memory copy, so the
    /// service would be enrolled with this device holding nothing.
    ///
    /// - Parameter record: the binding to hold, replacing the entry point's earlier one.
    func remember(_ record: AttestedDevice) throws {
        try Self.lock.withLock {
            try write(load().with(record))
        }
    }

    /// Drops this entry point's binding.
    ///
    /// Throws when the rewrite fails, so a caller is never told a binding was
    /// dropped while it is still readable.
    ///
    /// - Parameter entry: the entry point whose binding is dropped.
    func forget(entry: String) throws {
        try Self.lock.withLock {
            try write(load().without(entry: entry))
        }
    }

    /// Drops this entry point's binding only while it is still the one given.
    ///
    /// For a caller that read a binding, went away, and came back: the entry point may hold a newly
    /// attested binding by now.
    ///
    /// - Parameter entry: the entry point whose binding is dropped.
    /// - Parameter record: the binding the caller read, the only one dropped.
    /// - Returns: whether the binding was still the one given and was dropped.
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
    /// One turn of the lock, because the two are one decision: a key minted in the gap between
    /// them is deleted by a clear that was never about it.
    ///
    /// - Parameter entry: the entry point whose binding and pending key are dropped.
    func forgetEverything(for entry: String) throws {
        try Self.lock.withLock {
            try write(load().without(entry: entry))

            let held = try loadPending()
            guard held.keyId(for: entry) != nil else { return }
            try writePending(held.without(entry: entry))
        }
    }

    // MARK: - Keys an attestation is part way through

    /// The key this entry point minted and has not finished attesting.
    ///
    /// - Parameter entry: the entry point whose unfinished key is asked for.
    /// - Returns: the minted key's id, or `nil` where no attestation is unfinished.
    func pendingKey(for entry: String) throws -> String? {
        try Self.lock.withLock { try loadPending().keyId(for: entry) }
    }

    /// Kept per entry point. A key can be attested once, so one entry point's key is
    /// no use to another, and a single slot let whichever started second overwrite
    /// the first.
    ///
    /// - Parameter keyId: the minted key's id, held until the attestation spends it.
    /// - Parameter entry: the entry point the key was minted for.
    func rememberPendingKey(_ keyId: String, for entry: String) throws {
        try Self.lock.withLock {
            try writePending(try loadPending().with(keyId, for: entry))
        }
    }

    /// Only this entry point's: removing every one takes away a retry another paypoint is part way through.
    ///
    /// Raises when the write fails: the caller drops the slot immediately before burning the key it
    /// names, and a spent key is refused every time it is reused.
    ///
    /// - Parameter entry: the entry point whose pending key is dropped.
    func forgetPendingKey(for entry: String) throws {
        try Self.lock.withLock {
            let held = try loadPending()
            guard held.keyId(for: entry) != nil else { return }
            try writePending(held.without(entry: entry))
        }
    }

    private func loadPending() throws -> PendingKeys {
        guard let raw = try storage.string(forKey: PayabliKeychainKey.pendingKeyId) else {
            return PendingKeys()
        }
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PendingKeys.self, from: data)
        else {
            logger.info("[attest] stored pending keys could not be decoded; discarding")
            try? storage.remove(forKey: PayabliKeychainKey.pendingKeyId)
            return PendingKeys()
        }
        return decoded
    }

    private func writePending(_ pending: PendingKeys) throws {
        guard !pending.keys.isEmpty else {
            try storage.remove(forKey: PayabliKeychainKey.pendingKeyId)
            return
        }
        guard let data = try? JSONEncoder().encode(pending),
              let raw = String(bytes: data, encoding: .utf8)
        else {
            throw TapToPayError(type: .sdkInternalError, reason: "The pending key could not be encoded", detail: nil)
        }
        try storage.set(raw, forKey: PayabliKeychainKey.pendingKeyId)
    }

    // MARK: - Under the lock

    /// Everything stored, empty when there is nothing to read, and a raise when the store could not
    /// answer.
    ///
    /// A record that will not decode is gone, and the item goes with it.
    ///
    /// - Returns: the stored bindings, empty where nothing decodes.
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
            throw TapToPayError(type: .sdkInternalError, reason: "The device binding could not be encoded", detail: nil)
        }
        try storage.set(raw, forKey: PayabliKeychainKey.deviceBindings)
    }
}
