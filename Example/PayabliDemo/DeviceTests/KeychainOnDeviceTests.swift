@testable import PayabliSDKTapToPay
import Security
import XCTest

/// What `KeychainStorage` does against a Keychain that answers.
///
/// The package's own `SecureStorageTests` ask the same questions and skip on every
/// host that runs them: an SPM test bundle is tool-hosted, so it has no app bundle,
/// no entitlement and no Keychain, and every call comes back
/// `errSecMissingEntitlement`. This bundle is hosted by the demo app, so the
/// answers here are the platform's. Nothing in this file skips.
final class KeychainOnDeviceTests: XCTestCase {
    private var service = ""
    private var storage = KeychainStorage()

    override func setUp() {
        super.setUp()
        // Its own service per test, so one test's leftovers cannot answer another's
        // read, and a failure leaves nothing behind for the next run.
        service = "com.payabli.devicetests.\(UUID().uuidString)"
        storage = KeychainStorage(service: service)
    }

    override func tearDown() {
        clearService()
        super.tearDown()
    }

    func testAStoredValueReadsBackAsItself() throws {
        try storage.set("hello_keychain", forKey: "sample_key")
        XCTAssertEqual(try storage.string(forKey: "sample_key"), "hello_keychain")
    }

    /// The distinction the read contract rests on. An absent item is the only
    /// answer that reads as nothing stored; every other status raises, which is
    /// what stops an enrolled device being reported as a new one.
    func testAKeyWithNoItemReadsAsNothingStored() throws {
        XCTAssertNil(try storage.string(forKey: "never_written"))
    }

    func testRemovingAKeyThatHasNoItemSucceeds() {
        XCTAssertNoThrow(try storage.remove(forKey: "never_written"))
    }

    func testARemovedKeyReadsAsNothingStored() throws {
        try storage.set("v", forKey: "sample_key")
        try storage.remove(forKey: "sample_key")
        XCTAssertNil(try storage.string(forKey: "sample_key"))
    }

    /// `ThisDeviceOnly` because a binding names a Secure Enclave key no backup
    /// carries, so a restored copy is an identity the new phone cannot sign for.
    /// Asserted against the attribute the Keychain actually holds.
    func testAStoredItemIsNotCarriedByABackup() throws {
        try storage.set("v", forKey: "sample_key")
        XCTAssertEqual(
            try accessibility(ofKey: "sample_key"),
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    /// An install that attested before the attribute existed is corrected when the
    /// store is opened, since the warm path only reads and would otherwise keep the
    /// old attribute for as long as the install lasts.
    func testOpeningTheStoreCorrectsAnItemABackupWouldCarry() throws {
        try writeDirectly(
            "v",
            forKey: PayabliKeychainKey.installId,
            accessible: kSecAttrAccessibleWhenUnlocked
        )
        XCTAssertEqual(
            try accessibility(ofKey: PayabliKeychainKey.installId),
            kSecAttrAccessibleWhenUnlocked as String,
            "the item under test was not written the old way"
        )

        _ = KeychainStorage(service: service)

        XCTAssertEqual(
            try accessibility(ofKey: PayabliKeychainKey.installId),
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    /// Writing over an item that already exists has to set the attribute too. The store is opened before
    /// the legacy item is written, so the sweep cannot have corrected it and this is `set` alone: it takes
    /// the update path rather than the add path the test above covers, and an update that names only the
    /// value leaves the old attribute in place for as long as the install lasts.
    func testRewritingAnExistingItemStopsItTravelling() throws {
        try writeDirectly(
            "before",
            forKey: PayabliKeychainKey.installId,
            accessible: kSecAttrAccessibleAfterFirstUnlock
        )

        try storage.set("after", forKey: PayabliKeychainKey.installId)

        XCTAssertEqual(
            try accessibility(ofKey: PayabliKeychainKey.installId),
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertEqual(try storage.string(forKey: PayabliKeychainKey.installId), "after")
    }

    /// Opening the store reads every key it knows about. Reading must not create one: an item written
    /// empty here would be a stored credential that nothing ever set, and every later read would find it.
    /// Asserted over every key rather than one, since a key absent from that list would not be swept and
    /// so would not show the regression.
    func testOpeningTheStoreWritesNothingForAKeyThatHasNoItem() throws {
        _ = KeychainStorage(service: service)

        for key in PayabliKeychainKey.all {
            XCTAssertNil(try storage.string(forKey: key), key)
        }
    }

    /// Correcting the attribute must not read the value and write it back: an item
    /// deleted in between would be put back from the copy in hand.
    func testCorrectingTheAttributeKeepsTheStoredValue() throws {
        try writeDirectly(
            "kept",
            forKey: PayabliKeychainKey.installId,
            accessible: kSecAttrAccessibleWhenUnlocked
        )
        let reopened = KeychainStorage(service: service)
        XCTAssertEqual(try reopened.string(forKey: PayabliKeychainKey.installId), "kept")
    }

    // MARK: - Reading the Keychain directly

    private func accessibility(ofKey key: String) throws -> String {
        var item: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        let attributes = try XCTUnwrap(item as? [String: Any], "the item carried no attributes")
        return try XCTUnwrap(attributes[kSecAttrAccessible as String] as? String)
    }

    private func writeDirectly(_ value: String, forKey key: String, accessible: CFString) throws {
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: accessible
        ] as CFDictionary, nil)
        XCTAssertEqual(status, errSecSuccess, "the item under test could not be written")
    }

    private func clearService() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ] as CFDictionary)
    }
}
