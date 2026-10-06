@testable import PayabliSDKCore
import Security
import XCTest

/// The package's test host holds no Keychain entitlement, so the platform refuses every call. A refused
/// store raises on every operation and never answers as an empty one.
final class KeychainStorageRefusalTests: XCTestCase {
    private let storage = KeychainStorage(
        service: "com.payabli.tests.\(UUID().uuidString)",
        migrating: [InstallIdentifier.storageKey]
    )

    func testAReadTheStoreRefusesRaises() {
        assertRefused { _ = try storage.string(forKey: "k") }
        assertRefused { _ = try storage.accessGroup(forKey: "k") }
    }

    func testAWriteTheStoreRefusesRaises() {
        assertRefused { try storage.set("v", forKey: "k") }
    }

    func testARemovalTheStoreRefusesRaises() {
        assertRefused { try storage.remove(forKey: "k") }
        assertRefused { try storage.removeAll() }
    }

    private func assertRefused(_ call: () throws -> Void, line: UInt = #line) {
        XCTAssertThrowsError(try call(), line: line) { error in
            guard case let KeychainStorage.KeychainError.underlying(status) = error else {
                return XCTFail("raised \(error)", line: line)
            }
            XCTAssertEqual(status, errSecMissingEntitlement, line: line)
        }
    }
}
