@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import Security
import XCTest

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

    // MARK: - What a missing Keychain looks like

    /// A test host with no Keychain to answer with, as opposed to a Keychain that
    /// answered and said no. An SPM test target is tool-hosted, so it has no app
    /// bundle and no entitlement, and every call comes back the same way.
    ///
    /// Anything else is a real answer and fails the test rather than skipping it.
    private static let hostHasNoKeychain: Set<OSStatus> = [
        errSecMissingEntitlement,
        errSecNotAvailable
    ]

    private func skipIfHostHasNoKeychain(_ status: OSStatus, whileDoing what: String) throws {
        guard status != errSecSuccess else { return }
        guard Self.hostHasNoKeychain.contains(status) else {
            XCTFail("\(what) failed with OSStatus \(status)")
            return
        }
        throw XCTSkip("no Keychain in this test host (OSStatus \(status)); covered by device QA (§12.3).")
    }

    // MARK: - KeychainStorage

    /// Keychain is only available on real devices / simulators with an
    /// unlocked default keychain. CI on macOS tools may not have one, and
    /// GitHub-hosted iOS Simulator runners routinely reject Keychain APIs
    /// with errSecMissingEntitlement (-34018) because the xctest host
    /// bundle has no `keychain-access-groups` entitlement. These tests
    /// skip gracefully when the store is unavailable — keychain
    /// round-trip is covered by on-device QA (PRD §12.3).
    func testKeychainRoundTripIfAvailable() throws {
        #if os(macOS) && !targetEnvironment(simulator)
            throw XCTSkip("Keychain services require a running keychaind; covered by device QA (§12.3).")
        #else
            let storage = KeychainStorage(service: "com.payabli.tests.\(UUID().uuidString)")
            defer { storage.removeAll() }

            do {
                try storage.set("hello_keychain", forKey: "sample_key")
            } catch let KeychainStorage.KeychainError.underlying(status) {
                try skipIfHostHasNoKeychain(status, whileDoing: "writing an item")
                return
            }

            XCTAssertEqual(storage.string(forKey: "sample_key"), "hello_keychain")

            storage.remove(forKey: "sample_key")
            XCTAssertNil(storage.string(forKey: "sample_key"))
        #endif
    }

    /// The attribute both write paths carry, asserted without a Keychain, since no
    /// test host here has one to answer with.
    func testWritesCarryTheDeviceOnlyAttribute() {
        let attributes = KeychainStorage.writeAttributes(Data("v".utf8))

        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
            "an item written with this attribute can be carried to another device by a backup"
        )
        XCTAssertEqual(attributes[kSecValueData as String] as? Data, Data("v".utf8))
    }

    /// Skips on the same terms as the round trip above.
    func testKeychainItemsAreWrittenForThisDeviceOnlyIfAvailable() throws {
        #if os(macOS) && !targetEnvironment(simulator)
            throw XCTSkip("Keychain services require a running keychaind; covered by device QA (§12.3).")
        #else
            let service = "com.payabli.tests.\(UUID().uuidString)"
            let storage = KeychainStorage(service: service)
            defer { storage.removeAll() }

            do {
                try storage.set("hello_keychain", forKey: "sample_key")
            } catch let KeychainStorage.KeychainError.underlying(status) {
                try skipIfHostHasNoKeychain(status, whileDoing: "writing an item")
                return
            }

            var item: CFTypeRef?
            let status = SecItemCopyMatching([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "sample_key",
                kSecReturnAttributes as String: true
            ] as CFDictionary, &item)

            XCTAssertEqual(status, errSecSuccess, "the item just written could not be read back")
            let attributes = try XCTUnwrap(item as? [String: Any])
            XCTAssertEqual(
                attributes[kSecAttrAccessible as String] as? String,
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
                "the item was written with an attribute that lets a backup carry it to another device"
            )
        #endif
    }

    /// An existing item is corrected by its next write, which takes the update
    /// path rather than the add path the test above covers.
    func testRewritingALegacyItemStopsItTravellingIfAvailable() throws {
        #if os(macOS) && !targetEnvironment(simulator)
            throw XCTSkip("Keychain services require a running keychaind; covered by device QA (§12.3).")
        #else
            let service = "com.payabli.tests.\(UUID().uuidString)"
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "sample_key"
            ]
            defer { SecItemDelete(base as CFDictionary) }

            var legacy = base
            legacy[kSecValueData as String] = Data("before".utf8)
            legacy[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            try skipIfHostHasNoKeychain(SecItemAdd(legacy as CFDictionary, nil), whileDoing: "seeding a legacy item")

            try KeychainStorage(service: service).set("after", forKey: "sample_key")

            var item: CFTypeRef?
            var query = base
            query[kSecReturnAttributes as String] = true
            XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)
            let attributes = try XCTUnwrap(item as? [String: Any])
            XCTAssertEqual(
                attributes[kSecAttrAccessible as String] as? String,
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
                "rewriting an existing item left it with the attribute a backup can carry"
            )
        #endif
    }

    /// The warm path only reads, so an install that already attested never writes
    /// again and would keep the old attribute for good. The sweep is what rewrites
    /// it, and it has to cover every key the SDK stores.
    func testTheSweepCoversEveryKeyTheSDKStores() {
        XCTAssertEqual(
            Set(PayabliKeychainKey.all),
            [PayabliKeychainKey.keyId, PayabliKeychainKey.deviceId, PayabliKeychainKey.pendingKeyId]
        )
    }

    /// Skips on the same terms as the round trip above.
    func testTheSweepRewritesAStoredItemAndKeepsItsValueIfAvailable() throws {
        #if os(macOS) && !targetEnvironment(simulator)
            throw XCTSkip("Keychain services require a running keychaind; covered by device QA (§12.3).")
        #else
            let service = "com.payabli.tests.\(UUID().uuidString)"
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: PayabliKeychainKey.deviceId
            ]
            defer { SecItemDelete(base as CFDictionary) }

            var legacy = base
            legacy[kSecValueData as String] = Data("device-77".utf8)
            legacy[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            try skipIfHostHasNoKeychain(SecItemAdd(legacy as CFDictionary, nil), whileDoing: "seeding a legacy item")

            // Opening the store is what runs the sweep.
            let storage = KeychainStorage(service: service)

            var item: CFTypeRef?
            var query = base
            query[kSecReturnAttributes as String] = true
            XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)
            let attributes = try XCTUnwrap(item as? [String: Any])
            XCTAssertEqual(
                attributes[kSecAttrAccessible as String] as? String,
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
                "the sweep left the item with the attribute a backup can carry"
            )
            XCTAssertEqual(storage.string(forKey: PayabliKeychainKey.deviceId), "device-77")
        #endif
    }

    /// A key with nothing stored under it is skipped, so a fresh install does not
    /// write empty items.
    func testTheSweepStoresNothingForAKeyThatHasNoItemIfAvailable() throws {
        #if os(macOS) && !targetEnvironment(simulator)
            throw XCTSkip("Keychain services require a running keychaind; covered by device QA (§12.3).")
        #else
            let storage = KeychainStorage(service: "com.payabli.tests.\(UUID().uuidString)")
            defer { storage.removeAll() }

            for key in PayabliKeychainKey.all {
                XCTAssertNil(storage.string(forKey: key), key)
            }
        #endif
    }

    // MARK: - Storage key constants

    func testStorageKeyConstantsMatchPRD() {
        XCTAssertEqual(PayabliKeychainKey.keyId, "com.payabli.ttp.keyId")
        XCTAssertEqual(PayabliKeychainKey.deviceId, "com.payabli.ttp.deviceId")
    }
}
