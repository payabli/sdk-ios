import Foundation
@testable import PayabliSDKPayIn

final class MockAppAttestor: AppAttestor, @unchecked Sendable {
    var isSupported: Bool = true
    var generatedKeyId: String = "mock_keyId"
    var attestationPayload: Data = Data("attest".utf8)
    var assertionPayload: Data = Data("assert".utf8)

    private(set) var generateKeyCalls = 0
    private(set) var attestKeyCalls = 0
    private(set) var generateAssertionCalls = 0

    func generateKey() async throws -> String {
        generateKeyCalls += 1
        return generatedKeyId
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        attestKeyCalls += 1
        return attestationPayload
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        generateAssertionCalls += 1
        return assertionPayload
    }
}
