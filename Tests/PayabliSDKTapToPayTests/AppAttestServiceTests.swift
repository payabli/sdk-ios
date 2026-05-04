import XCTest
import PayabliSDKCore
@testable import PayabliSDKTapToPay

final class AppAttestServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeAttest(
        storage: SecureStorage = InMemorySecureStorage()
    ) -> (AppAttestService, MockAppAttestor, PayabliAuth) {
        let session = StubURLProtocol.makeSession()
        let service = PayabliService(environment: .sandbox, session: session)
        let config = PayabliConfig(
            accessToken: "seed",
            entryPoint: "myEntry",
            environment: .sandbox
        )
        let auth = PayabliAuth(config: config)
        let attestor = MockAppAttestor()
        let sut = AppAttestService(
            service: service,
            auth: auth,
            attestor: attestor,
            storage: storage,
            hardwareIdProvider: { "fixed-hw-id" },
            deviceNameProvider: { "iPhone" },
            modelProvider: { "iPhone15,2" },
            osVersionProvider: { "17.0" }
        )
        return (sut, attestor, auth)
    }

    private func response(_ status: Int, body: Data, url: URL) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                         headerFields: ["Content-Type": "application/json"])!, body)
    }

    private static func envelope(responseData: [String: Any]) -> Data {
        let payload: [String: Any] = [
            "responseCode": 1,
            "isSuccess": true,
            "responseText": "OK",
            "responseData": responseData
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - First-run flow

    func testFirstRunAttestHitsAllThreeEndpoints() async throws {
        let pathsBox = PathsBox()
        StubURLProtocol.handler = { request in
            pathsBox.append(request.url!.path)
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                        Self.envelope(responseData: ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"]))
            case "/api/v2/device/taptopay/register":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                        Self.envelope(responseData: ["deviceId": "dev_1"]))
            case "/api/v2/device/taptopay/attest":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                        Self.envelope(responseData: ["ok": true]))
            default:
                XCTFail("unexpected path: \(request.url!.path)")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
        }

        let storage = InMemorySecureStorage()
        let (sut, attestor, _) = makeAttest(storage: storage)

        XCTAssertFalse(sut.isAlreadyAttested)
        let result = try await sut.attest(entry: "myEntry", appId: "TEAM.bundle.id")

        XCTAssertEqual(result.deviceId, "dev_1")
        XCTAssertEqual(result.keyId, "mock_keyId")
        XCTAssertEqual(attestor.generateKeyCalls, 1)
        XCTAssertEqual(attestor.attestKeyCalls, 1)
        XCTAssertEqual(pathsBox.values, [
            "/api/v2/device/taptopay/challenge",
            "/api/v2/device/taptopay/register",
            "/api/v2/device/taptopay/attest"
        ])

        // Persistence
        XCTAssertTrue(sut.isAlreadyAttested)
        XCTAssertEqual(storage.string(forKey: PayabliKeychainKey.keyId), "mock_keyId")
        XCTAssertEqual(storage.string(forKey: PayabliKeychainKey.deviceId), "dev_1")
    }

    // MARK: - Pending activation

    func testPendingStatusCompletesAttestationThenThrowsActivationError() async throws {
        let pathsBox = PathsBox()
        StubURLProtocol.handler = { request in
            pathsBox.append(request.url!.path)
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                        Self.envelope(responseData: ["challengeId": "c", "challenge": "Y2hhbGxlbmdl"]))
            case "/api/v2/device/taptopay/register":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                        Self.envelope(responseData: ["deviceId": "dev_pending", "status": "pending"]))
            case "/api/v2/device/taptopay/attest":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                        Self.envelope(responseData: ["ok": true]))
            default:
                XCTFail("unexpected path: \(request.url!.path)")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
        }

        let storage = InMemorySecureStorage()
        let (sut, attestor, _) = makeAttest(storage: storage)
        do {
            _ = try await sut.attest(entry: "myEntry", appId: "x")
            XCTFail("expected throw")
        } catch PayabliTTPError.devicePendingActivation {
            // Pending must still surface, BUT only after the full attestation
            // (including /attest) has completed so that /activate can later
            // verify the Apple assertion and find the DeviceAttestations row.
            XCTAssertEqual(pathsBox.values, [
                "/api/v2/device/taptopay/challenge",
                "/api/v2/device/taptopay/register",
                "/api/v2/device/taptopay/attest"
            ])
            XCTAssertEqual(attestor.generateKeyCalls, 1)
            XCTAssertEqual(attestor.attestKeyCalls, 1)
            XCTAssertEqual(storage.string(forKey: PayabliKeychainKey.deviceId), "dev_pending")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Assertion generation

    func testGenerateAssertionProducesHeaders() async throws {
        let storage = InMemorySecureStorage()
        try storage.set("cached_keyId", forKey: PayabliKeychainKey.keyId)
        try storage.set("cached_deviceId", forKey: PayabliKeychainKey.deviceId)

        let (sut, attestor, _) = makeAttest(storage: storage)
        let headers = try await sut.generateAssertion()
        XCTAssertEqual(headers.keyId, "cached_keyId")
        XCTAssertEqual(headers.deviceId, "cached_deviceId")
        XCTAssertFalse(headers.assertion.isEmpty)
        XCTAssertFalse(headers.timestamp.isEmpty)
        XCTAssertEqual(attestor.generateAssertionCalls, 1)
    }

    func testGenerateAssertionFailsWithoutState() async throws {
        let (sut, _, _) = makeAttest()
        do {
            _ = try await sut.generateAssertion()
            XCTFail("expected throw")
        } catch PayabliTTPError.attestationFailed {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - clearCache

    func testClearCacheRemovesKeychainState() async throws {
        let storage = InMemorySecureStorage()
        try storage.set("a", forKey: PayabliKeychainKey.keyId)
        try storage.set("b", forKey: PayabliKeychainKey.deviceId)
        let (sut, _, _) = makeAttest(storage: storage)

        sut.clearCache()
        XCTAssertFalse(sut.isAlreadyAttested)
    }
}

/// Thread-safe box so the stub handler can record the order of paths it sees.
private final class PathsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var values: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func append(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(s)
    }
}
