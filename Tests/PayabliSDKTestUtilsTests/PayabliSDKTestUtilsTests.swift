import XCTest
import PayabliSDKTestUtils

final class PayabliSDKTestUtilsTests: XCTestCase {
    func testStubURLProtocolMakeSessionReturnsConfiguredSession() {
        let session = StubURLProtocol.makeSession()
        let protocols = session.configuration.protocolClasses ?? []
        XCTAssertTrue(protocols.contains { $0 == StubURLProtocol.self })
    }

    func testInMemorySecureStorageRoundTrips() throws {
        let storage = InMemorySecureStorage()
        try storage.set("hello", forKey: "key")
        XCTAssertEqual(storage.string(forKey: "key"), "hello")
        storage.remove(forKey: "key")
        XCTAssertNil(storage.string(forKey: "key"))
    }

    func testMockTapToPayProviderHasMockProviderId() {
        XCTAssertEqual(MockTapToPayProvider.providerId, "mock")
        let mock = MockTapToPayProvider()
        XCTAssertNotNil(mock)
    }
}
