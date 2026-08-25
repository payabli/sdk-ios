import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

final class PayabliSDKTestUtilsTests: XCTestCase {
    func testStubURLProtocolMakeSessionReturnsConfiguredSession() {
        let session = StubURLProtocol.makeSession()
        let protocols = session.configuration.protocolClasses ?? []
        XCTAssertTrue(protocols.contains { $0 == StubURLProtocol.self })
    }

    func testInMemorySecureStorageRoundTrips() throws {
        let storage = InMemorySecureStorage()
        try storage.set("hello", forKey: "key")
        XCTAssertEqual(try storage.string(forKey: "key"), "hello")
        try storage.remove(forKey: "key")
        XCTAssertNil(try storage.string(forKey: "key"))
    }

    /// The double drops what a refusal named, as `AppAttestService` does.
    func testTheAttestationDoubleDropsTheBindingARefusalNamed() throws {
        let attestation = MockDeviceAttestationService()
        attestation.bindings = ["entryA": "devA"]

        XCTAssertTrue(
            try attestation.forgetRefusedBinding(
                entry: "entryA",
                deviceId: "devA",
                keyId: MockDeviceAttestationService.defaultKeyId
            )
        )
        XCTAssertNil(try attestation.cachedDeviceId(for: "entryA"))
    }

    /// The key is part of what a refusal named. A binding that kept its handle
    /// across a key rotation is a different binding, and production keeps it, so a
    /// double that drops it lets a facade test pass on behaviour that does not
    /// exist.
    func testTheAttestationDoubleKeepsABindingWhoseKeyChanged() throws {
        let attestation = MockDeviceAttestationService()
        attestation.bindings = ["entryA": "devA"]
        attestation.bindingKeys = ["entryA": "keyNew"]

        XCTAssertFalse(
            try attestation.forgetRefusedBinding(entry: "entryA", deviceId: "devA", keyId: "keyOld")
        )
        XCTAssertEqual(try attestation.cachedDeviceId(for: "entryA"), "devA")
    }

    /// A refusal about a handle this paypoint no longer holds drops nothing.
    func testTheAttestationDoubleKeepsABindingEnrolledSince() throws {
        let attestation = MockDeviceAttestationService()
        attestation.bindings = ["entryA": "devNew"]

        XCTAssertFalse(
            try attestation.forgetRefusedBinding(
                entry: "entryA",
                deviceId: "devOld",
                keyId: MockDeviceAttestationService.defaultKeyId
            )
        )
        XCTAssertEqual(try attestation.cachedDeviceId(for: "entryA"), "devNew")
    }

    /// The assertion names the key the binding holds, so a caller comparing what it
    /// presented against what is stored sees them agree.
    func testTheAssertionNamesTheKeyTheBindingHolds() async throws {
        let attestation = MockDeviceAttestationService()
        attestation.bindings = ["entryA": "devA"]
        attestation.bindingKeys = ["entryA": "keyA"]

        let headers = try await attestation.generateAssertion(for: "entryA")
        XCTAssertEqual(headers.deviceId, "devA")
        XCTAssertEqual(headers.keyId, "keyA")
    }

    func testMockTapToPayProviderHasMockProviderId() {
        XCTAssertEqual(MockTapToPayProvider.providerId, "mock")
        let mock = MockTapToPayProvider()
        XCTAssertNotNil(mock)
    }
}
