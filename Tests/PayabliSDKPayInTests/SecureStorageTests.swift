import XCTest
@testable import PayabliSDKPayIn

final class SecureStorageTests: XCTestCase {

    // MARK: - InMemorySecureStorage

    func testInMemoryRoundTrip() throws {
        let storage: SecureStorage = InMemorySecureStorage()
        try storage.set("value_xyz", forKey: "key_a")
        XCTAssertEqual(storage.string(forKey: "key_a"), "value_xyz")
    }

    func testInMemoryRemove() throws {
        let storage = InMemorySecureStorage()
        try storage.set("v", forKey: "k")
        storage.remove(forKey: "k")
        XCTAssertNil(storage.string(forKey: "k"))
    }

    func testInMemoryMissingKeyReturnsNil() {
        let storage = InMemorySecureStorage()
        XCTAssertNil(storage.string(forKey: "never_set"))
    }

    // MARK: - KeychainStorage

    /// Keychain is only available on real devices / simulators with an
    /// unlocked default keychain. CI on macOS tools may not have one — so
    /// these tests skip gracefully when the store is unavailable.
    func testKeychainRoundTripIfAvailable() throws {
        #if os(macOS) && !targetEnvironment(simulator)
        throw XCTSkip("Keychain services require a running keychaind; covered by device QA (§12.3).")
        #else
        let storage = KeychainStorage(service: "com.payabli.tests.\(UUID().uuidString)")
        defer { storage.removeAll() }

        try storage.set("hello_keychain", forKey: "sample_key")
        XCTAssertEqual(storage.string(forKey: "sample_key"), "hello_keychain")

        storage.remove(forKey: "sample_key")
        XCTAssertNil(storage.string(forKey: "sample_key"))
        #endif
    }

    // MARK: - Storage key constants

    func testStorageKeyConstantsMatchPRD() {
        XCTAssertEqual(PayabliKeychainKey.keyId, "com.payabli.ttp.keyId")
        XCTAssertEqual(PayabliKeychainKey.deviceId, "com.payabli.ttp.deviceId")
    }
}
