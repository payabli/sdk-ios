import Foundation

/// Port: device attestation and assertion generation.
/// Production adapter: AppAttestAdapter (DCAppAttestService).
/// Future adapter: PlayIntegrityAdapter (Android).
/// Test adapter: MockDeviceAttester.
protocol DeviceAttesting {
    var state: AttestationState { get }
    var keyId: String? { get }
    var needsAttestation: Bool { get }

    static var isSupported: Bool { get }

    func generateKey() async throws -> String
    func attestKey(_ keyId: String, challenge: Data) async throws -> Data
    func persistKeyId(_ keyId: String) throws
    func discardKey()
    func generateAssertion(requestData: Data) async throws -> Data
}
