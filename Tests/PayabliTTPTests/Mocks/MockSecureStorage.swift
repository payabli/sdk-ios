import Foundation
@testable import PayabliTTP

final class MockSecureStorage: SecureStorage, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func save(key: String, data: Data) throws {
        store[key] = data
    }

    func load(key: String) -> Data? {
        store[key]
    }

    func delete(key: String) {
        store.removeValue(forKey: key)
    }
}
