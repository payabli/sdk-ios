@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import Security
import XCTest

/// What the store answers, and the difference between holding nothing and being
/// unable to say.
final class AttestedDeviceStoreTests: XCTestCase {
    // MARK: - Nothing stored, against a store that could not be read

    func testARecordRoundTrips() throws {
        let store = AttestedDeviceStore(storage: InMemorySecureStorage())
        try store.remember(AttestedDevice(entry: "entryA", deviceId: "dev_a", keyId: "key_a"))

        XCTAssertEqual(try store.binding(for: "entryA")?.deviceId, "dev_a")
    }

    func testNothingStoredReadsAsNothingRatherThanAFailure() throws {
        let store = AttestedDeviceStore(storage: InMemorySecureStorage())

        XCTAssertNil(try store.binding(for: "entryA"))
    }

    /// A record in a shape this version cannot read is gone, and the item goes with
    /// it, so the next enrolment is not deciding against bytes nothing can parse.
    func testARecordThatWillNotDecodeReadsAsNothingAndIsDropped() throws {
        let storage = InMemorySecureStorage()
        try storage.set("{not-bindings", forKey: PayabliKeychainKey.deviceBindings)

        let store = AttestedDeviceStore(storage: storage)

        XCTAssertNil(try store.binding(for: "entryA"))
        XCTAssertNil(
            try storage.string(forKey: PayabliKeychainKey.deviceBindings),
            "the item that would not decode is still there for the next read to fail on"
        )
    }

    /// A record whose fields are not the ones this version writes reads as nothing
    /// rather than as a binding with empty fields.
    func testARecordMissingItsFieldsReadsAsNothingAndIsDropped() throws {
        let storage = InMemorySecureStorage()
        try storage.set(#"{"bindings":[{"entry":"entryA"}]}"#, forKey: PayabliKeychainKey.deviceBindings)

        let store = AttestedDeviceStore(storage: storage)

        XCTAssertNil(try store.binding(for: "entryA"))
        XCTAssertNil(try storage.string(forKey: PayabliKeychainKey.deviceBindings))
    }

    /// A store that could not be read raises. Read as nothing, the cold sequence
    /// runs and registers a second device for a paypoint that already has one.
    func testAStoreThatCouldNotBeReadIsRaisedNeverReadAsNothingStored() throws {
        let storage = InMemorySecureStorage()
        let store = AttestedDeviceStore(storage: storage)
        try store.remember(AttestedDevice(entry: "entryA", deviceId: "dev_a", keyId: "key_a"))

        storage.readFailure = KeychainStorage.KeychainError.underlying(errSecInteractionNotAllowed)

        XCTAssertThrowsError(try store.binding(for: "entryA")) { error in
            guard case let KeychainStorage.KeychainError.underlying(status) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(status, errSecInteractionNotAllowed)
        }
    }

    // MARK: - The read a mutation starts from

    /// Taken as empty, the write below replaces every other paypoint's binding with
    /// just this one.
    func testAFailedReadNeverLetsAWriteDropAnotherPaypointsBinding() throws {
        let storage = InMemorySecureStorage()
        let store = AttestedDeviceStore(storage: storage)
        try store.remember(AttestedDevice(entry: "entryA", deviceId: "dev_a", keyId: "key_a"))

        let stored = try XCTUnwrap(storage.string(forKey: PayabliKeychainKey.deviceBindings))
        storage.readFailure = KeychainStorage.KeychainError.underlying(errSecInteractionNotAllowed)

        XCTAssertThrowsError(
            try store.remember(AttestedDevice(entry: "entryB", deviceId: "dev_b", keyId: "key_b"))
        )

        storage.readFailure = nil
        XCTAssertEqual(
            try storage.string(forKey: PayabliKeychainKey.deviceBindings),
            stored,
            "the write started from an empty list and dropped entryA's binding"
        )
    }

    /// The same consequence for the pending keys: a paypoint part way through an
    /// attestation loses the key it minted.
    func testAFailedReadNeverLetsAPendingKeyDropAnother() throws {
        let storage = InMemorySecureStorage()
        let store = AttestedDeviceStore(storage: storage)
        try store.rememberPendingKey("key_a", for: "entryA")

        storage.readFailure = KeychainStorage.KeychainError.underlying(errSecInteractionNotAllowed)
        XCTAssertThrowsError(try store.rememberPendingKey("key_b", for: "entryB"))

        storage.readFailure = nil
        XCTAssertEqual(try store.pendingKey(for: "entryA"), "key_a")
    }

    // MARK: - A mutation the store refused

    /// A drop the store refused is raised, so nothing tells a caller the binding is
    /// gone while it is still readable. A binding that outlives its own removal
    /// sends the same refused handle on the next warm start.
    func testADropTheStoreRefusedIsRaised() throws {
        let storage = WriteRefusingStorage()
        let store = AttestedDeviceStore(storage: storage)
        try store.remember(AttestedDevice(entry: "entryA", deviceId: "dev_a", keyId: "key_a"))
        try store.remember(AttestedDevice(entry: "entryB", deviceId: "dev_b", keyId: "key_b"))

        storage.refusesWrites = true
        XCTAssertThrowsError(try store.forget(entry: "entryA"))

        storage.refusesWrites = false
        XCTAssertEqual(
            try store.binding(for: "entryA")?.deviceId,
            "dev_a",
            "the drop was reported as done and the binding is gone, so there is nothing to raise about"
        )
    }

    /// Dropping a pending key the store refused to rewrite is raised, because the
    /// caller spends the key it names immediately afterwards and a key can be
    /// attested once.
    func testAPendingDropTheStoreRefusedIsRaised() throws {
        let storage = WriteRefusingStorage()
        let store = AttestedDeviceStore(storage: storage)
        try store.rememberPendingKey("key_a", for: "entryA")
        try store.rememberPendingKey("key_b", for: "entryB")

        storage.refusesWrites = true
        XCTAssertThrowsError(try store.forgetPendingKey(for: "entryA"))

        storage.refusesWrites = false
        XCTAssertEqual(try store.pendingKey(for: "entryA"), "key_a")
    }

    /// A conditional drop takes the record it was given and nothing else.
    func testAConditionalDropTakesTheRecordItWasGiven() throws {
        let store = AttestedDeviceStore(storage: InMemorySecureStorage())
        let record = AttestedDevice(entry: "entryA", deviceId: "dev_a", keyId: "key_a")
        try store.remember(record)

        XCTAssertTrue(try store.forget(entry: "entryA", ifStill: record))
        XCTAssertNil(try store.binding(for: "entryA"))
    }

    /// A record replaced since it was read is not the record the caller asked
    /// about, so it stays. This is the caller that read a binding, went away to ask
    /// the platform about it, and came back to an entry point holding something
    /// newer.
    func testAConditionalDropLeavesARecordReplacedSinceItWasRead() throws {
        let store = AttestedDeviceStore(storage: InMemorySecureStorage())
        let read = AttestedDevice(entry: "entryA", deviceId: "dev_old", keyId: "key_old")
        try store.remember(read)
        try store.remember(AttestedDevice(entry: "entryA", deviceId: "dev_new", keyId: "key_new"))

        XCTAssertFalse(try store.forget(entry: "entryA", ifStill: read))
        XCTAssertEqual(
            try store.binding(for: "entryA")?.deviceId,
            "dev_new",
            "the newer binding was dropped for a question asked about the older one"
        )
    }

    /// Dropping the only binding removes the item rather than storing an empty
    /// list, so nothing is left for a later read to carry forward.
    func testDroppingTheLastBindingRemovesTheItem() throws {
        let storage = InMemorySecureStorage()
        let store = AttestedDeviceStore(storage: storage)
        try store.remember(AttestedDevice(entry: "entryA", deviceId: "dev_a", keyId: "key_a"))

        try store.forget(entry: "entryA")

        XCTAssertNil(try storage.string(forKey: PayabliKeychainKey.deviceBindings))
    }
}

/// Reads like a working store and refuses writes on demand, so a test can reach a
/// mutation that fails after a read that did not.
final class WriteRefusingStorage: SecureStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]
    private var refuses = false

    var refusesWrites: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return refuses
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            refuses = newValue
        }
    }

    func string(forKey key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return store[key]
    }

    func set(_ value: String, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if refuses {
            throw KeychainStorage.KeychainError.underlying(errSecInteractionNotAllowed)
        }
        store[key] = value
    }

    func remove(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if refuses {
            throw KeychainStorage.KeychainError.underlying(errSecInteractionNotAllowed)
        }
        store.removeValue(forKey: key)
    }
}
