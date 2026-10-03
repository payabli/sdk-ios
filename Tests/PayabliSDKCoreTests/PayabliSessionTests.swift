@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

final class PayabliSessionTests: XCTestCase {
    override func tearDown() {
        PayabliSession.resetForTesting()
        super.tearDown()
    }

    func testSessionAcceptsCustomURLSession() async throws {
        let expectedBody = Data("{\"hello\":\"world\"}".utf8)
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/test-wiring")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                expectedBody
            )
        }
        defer { StubURLProtocol.handler = nil }

        let urlSession = StubURLProtocol.makeSession()
        let config = try PayabliConfig(
            entryPoint: "demo",
            environment: .sandbox,

            tokenProvider: { "tok" }
        )
        let session = PayabliSession(config: config, urlSession: urlSession)

        let request = PayabliRequest(method: .get, path: "/api/v2/test-wiring")
        let response = try await session.transport.perform(request)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body, expectedBody)
    }

    func testInitializeWithAnEqualConfigurationReturnsTheInstalledSession() throws {
        let first = try PayabliSession.initialize(config: makeConfig())
        let second = try PayabliSession.initialize(config: makeConfig())

        XCTAssertTrue(first === second)
    }

    func testInitializeRefusesADifferentEntryPointAndKeepsTheInstalledSession() throws {
        let installed = try PayabliSession.initialize(config: makeConfig())

        XCTAssertThrowsError(try PayabliSession.initialize(config: makeConfig(entryPoint: "other"))) { error in
            XCTAssertEqual((error as? PayabliGenericError)?.code, .invalidConfiguration)
        }
        XCTAssertTrue(try PayabliSession.initialize(config: makeConfig()) === installed)
    }

    func testInitializeRefusesADifferentEnvironment() throws {
        try PayabliSession.initialize(config: makeConfig())

        XCTAssertThrowsError(try PayabliSession.initialize(config: makeConfig(environment: .production))) { error in
            XCTAssertEqual((error as? PayabliGenericError)?.code, .invalidConfiguration)
        }
    }

    func testInitializeRefusesADifferentTelemetrySetting() throws {
        try PayabliSession.initialize(config: makeConfig())

        XCTAssertThrowsError(try PayabliSession.initialize(config: makeConfig(telemetryEnabled: false))) { error in
            XCTAssertEqual((error as? PayabliGenericError)?.code, .invalidConfiguration)
        }
    }

    func testConcurrentInitializeInstallsOneSession() throws {
        let config = try makeConfig()
        let installed = InstalledSessions()

        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if let session = try? PayabliSession.initialize(config: config) {
                installed.record(session)
            }
        }

        XCTAssertEqual(installed.distinctCount, 1)
        XCTAssertEqual(installed.total, 64)
    }

    func testASecondProviderDoesNotReplaceTheFirst() async throws {
        let session = try PayabliSession.initialize(config: makeConfig(tokenProvider: { "first" }))
        try PayabliSession.initialize(config: makeConfig(tokenProvider: { "second" }))

        let token = try await session.auth.currentAccessToken()
        XCTAssertEqual(token, "first")
    }

    private func makeConfig(
        entryPoint: String = "demo",
        environment: PayabliEnvironment = .sandbox,
        telemetryEnabled: Bool = true,
        tokenProvider: @escaping PayabliTokenRefresh = { "tok" }
    ) throws -> PayabliConfig {
        try PayabliConfig(
            entryPoint: entryPoint,
            environment: environment,
            tokenProvider: tokenProvider,
            telemetryEnabled: telemetryEnabled
        )
    }
}

private final class InstalledSessions: @unchecked Sendable {
    private let lock = NSLock()
    private var identities: [ObjectIdentifier] = []

    func record(_ session: PayabliSession) {
        lock.withLock { identities.append(ObjectIdentifier(session)) }
    }

    var total: Int {
        lock.withLock { identities.count }
    }

    var distinctCount: Int {
        lock.withLock { Set(identities).count }
    }
}
