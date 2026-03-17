import Foundation
@testable import PayabliTTP

final class MockDeviceAttester: DeviceAttesting {

    static var isSupported: Bool = true

    var state: AttestationState
    var keyId: String?
    var needsAttestation: Bool

    var generateKeyResult: String = "mock-key-id"
    var attestKeyResult: Data = Data("mock-attestation".utf8)
    var assertionResult: Data = Data("mock-assertion".utf8)

    var generateKeyCalled = false
    var attestKeyCalled = false
    var persistKeyIdCalled = false
    var discardKeyCalled = false
    var generateAssertionCalled = false

    var shouldFailGeneration = false
    var shouldFailAttestation = false
    var shouldFailAssertion = false

    init(alreadyAttested: Bool = false) {
        if alreadyAttested {
            state = .registered(keyId: "existing-key-id")
            keyId = "existing-key-id"
            needsAttestation = false
        } else {
            state = .notRegistered
            keyId = nil
            needsAttestation = true
        }
    }

    func generateKey() async throws -> String {
        generateKeyCalled = true
        if shouldFailGeneration {
            throw PayabliTTPError.attestationFailed("Mock generation failure")
        }
        return generateKeyResult
    }

    func attestKey(_ keyId: String, challenge: Data) async throws -> Data {
        attestKeyCalled = true
        if shouldFailAttestation {
            throw PayabliTTPError.attestationFailed("Mock attestation failure")
        }
        return attestKeyResult
    }

    func persistKeyId(_ keyId: String) throws {
        persistKeyIdCalled = true
        self.keyId = keyId
        state = .registered(keyId: keyId)
        needsAttestation = false
    }

    func discardKey() {
        discardKeyCalled = true
        keyId = nil
        state = .notRegistered
        needsAttestation = true
    }

    func generateAssertion(requestData: Data) async throws -> Data {
        generateAssertionCalled = true
        if shouldFailAssertion {
            throw PayabliTTPError.attestationFailed("Mock assertion failure")
        }
        return assertionResult
    }
}
