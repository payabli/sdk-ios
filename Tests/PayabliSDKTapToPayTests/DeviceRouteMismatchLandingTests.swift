@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// A refusal whose envelope names another code than its HTTP status, through the whole path a host's takes. On
/// `/activate` it is an activation refusal with no words, and the session keeps waiting for its code.
@available(iOS 16.7, *)
@MainActor
final class DeviceRouteMismatchLandingTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - /activate

    func testAnActivationRefusalNamingAnotherCodeLeavesTheSessionWaitingAndKeepsTheBinding() async throws {
        let cases: [(status: Int, code: Int, type: PayabliErrorType)] = [
            (404, 400, .unknown),
            (403, 400, .unknown),
            (404, 403, .unknown),
            (400, 404, .sdkInternalError),
            (400, 403, .sdkInternalError)
        ]
        for row in cases {
            let (ttp, attestation) = try await pendingTTP(activateAnswer: { request in
                Self.refusal(request, status: row.status, resultCode: row.code, reason: "Declined")
            })

            let thrown = await failure { try await ttp.activateDevice(activationCode: "123456") }

            let label = "status \(row.status) naming \(row.code)"
            XCTAssertEqual((thrown as? TapToPayError)?.type, row.type, "\(label): got \(thrown)")
            XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_1"), label)
            XCTAssertEqual(try attestation.binding(for: "myEntry")?.deviceId, "dev_1", "\(label): the binding is kept")
        }
    }

    // MARK: - Fixtures

    /// A facade left waiting for `dev_1`'s code by a `/config` 403, whose `/activate` answers with `activateAnswer`.
    private func pendingTTP(
        activateAnswer: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    ) async throws -> (PayabliTTP, AppAttestService) {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_1", keyId: "key_1", in: storage)
        StubURLProtocol.handler = { request in
            switch Self.route(of: request) {
            case "config":
                return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!, Data())
            case "activate":
                return activateAnswer(request)
            default:
                return AttestFixture.ok(request, ["ok": true])
            }
        }
        let (ttp, attestation) = try makeWiredTTP(storage: storage)
        _ = await failure { try await ttp.initialize() }
        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_1"), "the fixture did not leave the session waiting")
        return (ttp, attestation)
    }

    /// A facade whose attestation service sends its requests on the facade's own session.
    private func makeWiredTTP(
        storage: SecureStorage = InMemorySecureStorage()
    ) throws -> (PayabliTTP, AppAttestService) {
        let config = try PayabliConfig(entryPoint: "myEntry", environment: .sandbox, tokenProvider: { "seed" })
        let session = PayabliSession(config: config, urlSession: StubURLProtocol.makeSession())
        let attestation = AppAttestService(
            transport: session.transport,
            attestor: MockAppAttestor(),
            storage: storage,
            hardwareIdProvider: { "fixed-hw-id" },
            appIdProvider: { "TEAM.bundle.id" },
            modelProvider: { "iPhone15,2" },
            osVersionProvider: { "17.0" }
        )
        let ttp = PayabliTTP(
            session: session,
            provider: MockTapToPayProvider(),
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            // The session was never installed, so it reads as live only because the test says so.
            isLive: { true }
        )
        return (ttp, attestation)
    }

    /// What `block` threw. A success fails the test here, so the assertions after it are never quietly skipped.
    private func failure(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: () async throws -> Void
    ) async -> any Error {
        do {
            try await block()
            XCTFail("expected a failure, got a success", file: file, line: line)
            return CancellationError()
        } catch {
            return error
        }
    }

    private nonisolated static func route(of request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.replacingOccurrences(of: "/api/v2/device/taptopay/", with: "").components(separatedBy: "/")[0]
    }

    /// A refusal declining under `resultCode`, sent with `status`.
    private nonisolated static func refusal(
        _ request: URLRequest,
        status: Int,
        resultCode: Int,
        reason: String
    ) -> (HTTPURLResponse, Data) {
        let body: [String: Any] = [
            "isSuccess": false,
            "responseText": "Declined",
            "responseData": ["resultCode": resultCode, "resultText": reason]
        ]
        return (
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!,
            try! JSONSerialization.data(withJSONObject: body)
        )
    }
}
