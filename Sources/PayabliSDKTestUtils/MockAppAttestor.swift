import Foundation
import PayabliSDKTapToPay

/// Mock `AppAttestor` for unit tests that exercise attestation flows without
/// hitting `DCAppAttestService`.
public final class MockAppAttestor: AppAttestor, @unchecked Sendable {
    public var isSupported: Bool = true
    public var generatedKeyId: AppAttestKeyId = AppAttestKeyId("mock_keyId")
    public var attestationPayload: AttestationObject = AttestationObject(Data("attest".utf8))
    public var assertionPayload: AppAttestAssertion = AppAttestAssertion(Data("assert".utf8))

    public private(set) var generateKeyCalls = 0
    public private(set) var attestKeyCalls = 0
    public private(set) var generateAssertionCalls = 0

    public init() {}

    public func generateKey() async throws -> AppAttestKeyId {
        generateKeyCalls += 1
        return generatedKeyId
    }

    public func attestKey(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AttestationObject {
        attestKeyCalls += 1
        return attestationPayload
    }

    public func generateAssertion(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AppAttestAssertion {
        generateAssertionCalls += 1
        return assertionPayload
    }
}
