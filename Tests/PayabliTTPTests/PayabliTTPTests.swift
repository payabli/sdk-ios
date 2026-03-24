import XCTest
@testable import PayabliTTP

final class PayabliTTPConfigurationTests: XCTestCase {

    func testConfigurationStoresValues() {
        let config = PayabliTTPConfiguration(
            apiKey: "pk_test",
            entry: "myapp",
            deviceId: "dev-123",
            appId: "TEAM123.com.test.app",
            environment: .qa,
            logLevel: .debug
        )

        XCTAssertEqual(config.apiKey, "pk_test")
        XCTAssertEqual(config.entry, "myapp")
        XCTAssertEqual(config.deviceId, "dev-123")
        XCTAssertEqual(config.appId, "TEAM123.com.test.app")
        XCTAssertEqual(config.environment, .qa)
        XCTAssertEqual(config.logLevel, .debug)
    }

    func testConfigurationDefaultValues() {
        let config = PayabliTTPConfiguration(
            apiKey: "pk_test",
            entry: "myapp",
            deviceId: "dev-456",
            appId: "TEAM123.com.test.app"
        )

        XCTAssertEqual(config.environment, .production)
        XCTAssertEqual(config.logLevel, .none)
    }

    func testEnvironmentBaseURLs() {
        XCTAssertEqual(PayabliTTPEnvironment.qa.baseURL.absoluteString, "https://api-qa.payabli.com")
        XCTAssertEqual(PayabliTTPEnvironment.sandbox.baseURL.absoluteString, "https://api-sandbox.payabli.com")
        XCTAssertEqual(PayabliTTPEnvironment.production.baseURL.absoluteString, "https://api.payabli.com")
    }
}

final class PayabliTTPErrorTests: XCTestCase {

    func testErrorDescriptions() {
        let errors: [PayabliTTPError] = [
            .notInitialized,
            .deviceNotSupported,
            .attestationFailed("bad key"),
            .networkError("timeout"),
            .backendError(statusCode: 401, message: "Unauthorized"),
            .decodingError("missing field"),
            .fiservError("NFC failed"),
            .sessionExpired,
            .invalidState("bad transition"),
            .unknown("something")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testBackendErrorIncludesStatusCode() {
        let error = PayabliTTPError.backendError(statusCode: 502, message: "Bad Gateway")
        XCTAssertTrue(error.errorDescription!.contains("502"))
    }
}

final class SecureStorageTests: XCTestCase {

    func testMockStorageSaveAndLoad() throws {
        let storage = MockSecureStorage()
        try storage.save(key: "test", string: "hello")

        XCTAssertEqual(storage.loadString(key: "test"), "hello")
    }

    func testMockStorageDelete() throws {
        let storage = MockSecureStorage()
        try storage.save(key: "test", string: "hello")
        storage.delete(key: "test")

        XCTAssertNil(storage.load(key: "test"))
    }

    func testDeviceIdFromConfiguration() {
        let config = PayabliTTPConfiguration(
            apiKey: "pk_test",
            entry: "myapp",
            deviceId: "dev-merchant-registered",
            appId: "TEAM123.com.test.app"
        )
        XCTAssertEqual(config.deviceId, "dev-merchant-registered")
    }
}
