@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import Security
import XCTest

final class SecureStorageTests: XCTestCase {
    // MARK: - InMemorySecureStorage

    func testInMemoryRoundTrip() throws {
        let storage: SecureStorage = InMemorySecureStorage()
        try storage.set("value_xyz", forKey: "key_a")
        XCTAssertEqual(try storage.string(forKey: "key_a"), "value_xyz")
    }

    func testInMemoryRemove() throws {
        let storage = InMemorySecureStorage()
        try storage.set("v", forKey: "k")
        try storage.remove(forKey: "k")
        XCTAssertNil(try storage.string(forKey: "k"))
    }

    func testInMemoryMissingKeyReturnsNil() throws {
        let storage = InMemorySecureStorage()
        XCTAssertNil(try storage.string(forKey: "never_set"))
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
            defer { try? storage.removeAll() }

            do {
                try storage.set("hello_keychain", forKey: "sample_key")
            } catch let KeychainStorage.KeychainError.underlying(status) {
                try skipIfHostHasNoKeychain(status, whileDoing: "writing an item")
                return
            }

            XCTAssertEqual(try storage.string(forKey: "sample_key"), "hello_keychain")

            try storage.remove(forKey: "sample_key")
            XCTAssertNil(try storage.string(forKey: "sample_key"))
        #endif
    }

    /// Which statuses a read answers `nil` for, asserted without a Keychain, since
    /// no test host here has one to answer with.
    ///
    /// Only the item being absent means nothing is stored. Every other status is a
    /// condition that passes, and answering `nil` for one reports a device that is
    /// already enrolled as a new one, which enrols it again.
    func testOnlyAMissingItemReadsAsNothingStored() {
        XCTAssertTrue(KeychainStorage.isMissing(errSecItemNotFound))

        for status in [
            errSecInteractionNotAllowed,
            errSecMissingEntitlement,
            errSecNotAvailable,
            errSecAuthFailed,
            errSecIO
        ] {
            XCTAssertFalse(
                KeychainStorage.isMissing(status),
                "OSStatus \(status) reads as nothing stored, so a device already enrolled enrols again"
            )
        }
    }

    /// Deleting what is not there is what the caller asked for, so it passes. Every
    /// other status is a store that could not be reached.
    func testOnlySuccessAndAnAbsentItemPassAWrite() {
        XCTAssertNoThrow(try KeychainStorage.check(errSecSuccess))
        XCTAssertNoThrow(try KeychainStorage.check(errSecItemNotFound))

        for status in [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecIO] {
            XCTAssertThrowsError(
                try KeychainStorage.check(status),
                "OSStatus \(status) passed, so a mutation that never landed reads as done"
            )
        }
    }

    /// The read reports what the Keychain answered, on any host.
    ///
    /// `isMissing` and `check` are asserted above; this is the call site that has to
    /// use them, and it cannot be reached by a host-specific test. A tool-hosted
    /// target cannot run on a device at all, so there is no host here whose Keychain
    /// answers normally, and asserting `nil` for a key never written passes equally
    /// on a host that refused the call. Asking the Keychain the same question
    /// directly is what makes the two distinguishable.
    func testAReadReportsWhatTheKeychainAnswered() throws {
        let service = "com.payabli.tests.\(UUID().uuidString)"
        let storage = KeychainStorage(service: service)

        var probe: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "never_written",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as CFDictionary, &probe)

        // Read outside the assertion: `XCTAssertNil` catches a throw from its own
        // autoclosure and records it as a failure, so the branch below is never
        // reached if the read is made inside one.
        let value: String?
        do {
            value = try storage.string(forKey: "never_written")
        } catch let KeychainStorage.KeychainError.underlying(raised) {
            XCTAssertEqual(raised, status, "the read raised a status the Keychain did not report")
            XCTAssertFalse(KeychainStorage.isMissing(status))
            return
        }

        XCTAssertNil(value)
        XCTAssertTrue(
            KeychainStorage.isMissing(status),
            "the Keychain answered OSStatus \(status) and the read reported nothing stored"
        )
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
            defer { try? storage.removeAll() }

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

    /// The sweep runs over `all`, and the names callers use come from the same
    /// cases, so a key cannot be stored under a name the sweep does not visit.
    func testEveryNameCallersUseIsSwept() {
        let names = [
            PayabliKeychainKey.deviceBindings,
            PayabliKeychainKey.pendingKeyId
        ]

        for name in names {
            XCTAssertTrue(PayabliKeychainKey.all.contains(name), name)
        }
        XCTAssertEqual(PayabliKeychainKey.all.count, PayabliKeychainKey.Stored.allCases.count)
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
                kSecAttrAccount as String: PayabliKeychainKey.deviceBindings
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
            XCTAssertEqual(
                try storage.string(forKey: PayabliKeychainKey.deviceBindings),
                "device-77",
                "the sweep changed the value, which it never reads"
            )
        #endif
    }

    /// A key with nothing stored under it is skipped, so a fresh install does not
    /// write empty items.
    ///
    /// Skips on the same terms as the round trip above, and has to: a host with no
    /// entitlement reports that from the read rather than answering nil, so without
    /// the skip this asserts nothing is stored on a host that cannot say.
    func testTheSweepStoresNothingForAKeyThatHasNoItemIfAvailable() throws {
        #if os(macOS) && !targetEnvironment(simulator)
            throw XCTSkip("Keychain services require a running keychaind; covered by device QA (§12.3).")
        #else
            let storage = KeychainStorage(service: "com.payabli.tests.\(UUID().uuidString)")
            defer { try? storage.removeAll() }

            for key in PayabliKeychainKey.all {
                // Read outside the assertion. `XCTAssertNil` takes an autoclosure,
                // so a throw inside one is caught by XCTest and reported as a
                // failure, and the skip below is never reached.
                let stored: String?
                do {
                    stored = try storage.string(forKey: key)
                } catch let KeychainStorage.KeychainError.underlying(status) {
                    try skipIfHostHasNoKeychain(status, whileDoing: "reading a key the sweep skipped")
                    return
                }
                XCTAssertNil(stored, key)
            }
        #endif
    }

    // MARK: - Storage key constants

    func testStorageKeyConstantsMatchPRD() {
        XCTAssertEqual(PayabliKeychainKey.deviceBindings, "com.payabli.ttp.deviceBindings")
        XCTAssertEqual(PayabliKeychainKey.pendingKeyId, "com.payabli.ttp.pendingKeyId")
    }

    /// The two items an install from before the bindings item may hold. Named
    /// here so removing one from the discard list fails.
    func testTheSupersededNamesAreTheOnesAlreadyOnDevices() {
        XCTAssertEqual(PayabliKeychainKey.superseded, [
            "com.payabli.ttp.keyId",
            "com.payabli.ttp.deviceId"
        ])
    }
}
