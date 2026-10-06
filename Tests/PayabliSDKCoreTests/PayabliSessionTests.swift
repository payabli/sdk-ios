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

    func testInitializeWithAnEqualConfigurationReturnsTheInstalledSession() async throws {
        let first = try await PayabliSession.initialize(config: makeConfig())
        let second = try await PayabliSession.initialize(config: makeConfig())

        XCTAssertTrue(first === second)
    }

    func testInitializeRefusesADifferentEntryPointAndKeepsTheInstalledSession() async throws {
        let installed = try await PayabliSession.initialize(config: makeConfig())

        await assertRefused(try makeConfig(entryPoint: "other"))
        let again = try await PayabliSession.initialize(config: makeConfig())
        XCTAssertTrue(again === installed)
    }

    func testInitializeRefusesADifferentEnvironment() async throws {
        try await PayabliSession.initialize(config: makeConfig())

        await assertRefused(try makeConfig(environment: .production))
    }

    func testInitializeRefusesADifferentTelemetrySetting() async throws {
        try await PayabliSession.initialize(config: makeConfig())

        await assertRefused(try makeConfig(telemetryEnabled: false))
    }

    func testConcurrentInitializeInstallsOneSession() async throws {
        let config = try makeConfig()
        let installed = InstalledSessions()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 64 {
                group.addTask {
                    if let session = try? await PayabliSession.initialize(config: config) {
                        installed.record(session)
                    }
                }
            }
        }

        XCTAssertEqual(installed.distinctCount, 1)
        XCTAssertEqual(installed.total, 64)
    }

    func testTheObjCReaderAnswersTheInstalledSessionsDeviceId() async throws {
        XCTAssertNil(PayabliSessionObjC.deviceId, "nothing is installed yet")

        let session = try await PayabliSession.initialize(config: makeConfig())

        XCTAssertEqual(PayabliSessionObjC.deviceId, session.deviceId)
    }

    func testASecondProviderDoesNotReplaceTheFirst() async throws {
        let session = try await PayabliSession.initialize(config: makeConfig(tokenProvider: { "first" }))
        try await PayabliSession.initialize(config: makeConfig(tokenProvider: { "second" }))

        let token = try await session.auth.currentAccessToken()
        XCTAssertEqual(token, "first")
    }

    private func assertRefused(
        _ config: @autoclosure () throws -> PayabliConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await PayabliSession.initialize(config: config())
            XCTFail("expected a different configuration to be refused", file: file, line: line)
        } catch {
            XCTAssertEqual((error as? PayabliGenericError)?.type, .invalidConfiguration, file: file, line: line)
        }
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
