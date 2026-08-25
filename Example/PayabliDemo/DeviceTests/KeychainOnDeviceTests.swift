import PayabliSDKTapToPay
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
