import Foundation
@testable import PayabliSDKPayIn

final class MockAppAttestor: AppAttestor, @unchecked Sendable {
    var isSupported: Bool = true
    var generatedKeyId: AppAttestKeyId = AppAttestKeyId("mock_keyId")
    var attestationPayload: AttestationObject = AttestationObject(Data("attest".utf8))
    var assertionPayload: AppAttestAssertion = AppAttestAssertion(Data("assert".utf8))

    private(set) var generateKeyCalls = 0
    private(set) var attestKeyCalls = 0
    private(set) var generateAssertionCalls = 0

    func generateKey() async throws -> AppAttestKeyId {
        generateKeyCalls += 1
        return generatedKeyId
    }

    func attestKey(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AttestationObject {
        attestKeyCalls += 1
        return attestationPayload
    }

    func generateAssertion(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AppAttestAssertion {
        generateAssertionCalls += 1
        return assertionPayload
    }
}
