@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// A device-route refusal no classifier recognises is read by its code, with HTTP's meanings, on every route, and lands
/// where that code's remedy is.
@available(iOS 16.7, *)
@MainActor
final class DeviceRouteRefusalTests: XCTestCase {
    private static let table: [(code: Int?, type: PayabliErrorType, landing: PayabliTTPSessionState)] = [
        (400, .sdkInternalError, .failed(reason: .sdkInternalError)),
        (401, .deviceSetupRequired, .failed(reason: .deviceSetupRequired)),
        (403, .devicePendingActivation, .pendingActivation(activationId: "dev_e")),
        (404, .entryPointRefused, .failed(reason: .configurationRejected)),
        (503, .serverError, .failed(reason: .serviceUnavailable)),
        (409, .unknown, .failed(reason: .serviceUnavailable)),
        (nil, .unknown, .failed(reason: .serviceUnavailable))
    ]

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testEachCodeIsReadWithHTTPsMeaningAndLandsOnItsRemedy() {
        for row in Self.table {
            let refusal = DeviceRouteRefusal.of(code: row.code, reason: "REASON-SENTINEL", httpStatus: 200)

            XCTAssertEqual(refusal.type, row.type, "code \(String(describing: row.code))")
            XCTAssertEqual(
                PayabliTTPSessionState.landing(for: refusal, registration: .held(activationId: "dev_e")),
                row.landing,
                "code \(String(describing: row.code))"
            )
        }
    }

    func testOnlyA401LandsOnSettingTheDeviceUpAgain() {
        for code in [400, 403, 404, 409, 500, 503] {
            let refusal = DeviceRouteRefusal.of(code: code, reason: "x", httpStatus: 200)
            XCTAssertNotEqual(
                PayabliTTPSessionState.landing(for: refusal, registration: .held(activationId: "dev_e")),
                .failed(reason: .deviceSetupRequired),
                "code \(code)"
            )
        }
    }

    func testAnUnclassifiedDeclineOnChallengeIsReadByItsCode() async throws {
        for row in Self.table where row.code != nil {
            StubURLProtocol.handler = { request in
                (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.decline(code: row.code!)
                )
            }
            let (sut, _, _) = try AttestFixture.makeService()

            do {
                _ = try await sut.attest(entry: "myEntry")
                XCTFail("expected the attestation to fail")
            } catch {
                let host = try XCTUnwrap(TapToPayErrorTranslation.hostError(for: error) as? TapToPayError)
                XCTAssertEqual(host.type, row.type, "code \(row.code!)")
                XCTAssertNil(host.rawCode, "a device route's code is its status, so it names no finer condition")
                XCTAssertEqual(host.httpStatus, 200)
            }
        }
    }

    func testAnUnclassifiedDeclineOnConfigIsReadByItsCodeAndLands() async throws {
        for row in Self.table where row.code != nil && row.code != 401 && row.code != 403 {
            StubURLProtocol.handler = { request in
                (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.decline(code: row.code!)
                )
            }
            let ttp = try makeTTP()

            do {
                try await ttp.initialize()
                XCTFail("expected initialize to fail")
            } catch let error as TapToPayError {
                XCTAssertEqual(error.type, row.type, "code \(row.code!)")
            }
            XCTAssertEqual(ttp.sessionState, row.landing, "code \(row.code!)")
        }
    }

    func testADeclineNamingNoCodeIsNotGivenTheStatusAsItsCode() async throws {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!,
                Self.decline(code: nil, reason: "REASON-SENTINEL")
            )
        }
        let (sut, _, _) = try AttestFixture.makeService()

        do {
            _ = try await sut.attest(entry: "myEntry")
            XCTFail("expected the attestation to fail")
        } catch {
            let host = try XCTUnwrap(TapToPayErrorTranslation.hostError(for: error) as? TapToPayError)
            XCTAssertNil(host.rawCode)
            XCTAssertEqual(host.httpStatus, 400)
            XCTAssertNotEqual(host.type, .sdkInternalError, "the status is not read as the refusal's code")
        }
    }

    func testADeclineWhoseCodeIsNotItsStatusIsReadAsTheStatusAlone() async throws {
        for (status, code) in [(403, 400), (404, 401), (400, 404)] {
            let mismatched = try await attestFailure(status: status, body: Self.decline(code: code))
            let bare = try await attestFailure(status: status, body: Data())
            XCTAssertEqual(mismatched.type, bare.type, "status \(status) naming \(code)")
            XCTAssertEqual(mismatched.httpStatus, status)
        }
    }

    func testAnAttestDeclineTheServiceCannotVerifyKeepsTheStatusItCameWith() async throws {
        let reason = "Attestation verification failed: Apple attestation root is unavailable."
        StubURLProtocol.handler = { request in
            switch request.url?.lastPathComponent {
            case "challenge":
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            case "register":
                return AttestFixture.ok(request, ["deviceId": "dev_1"])
            default:
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.decline(code: 400, reason: reason)
                )
            }
        }
        let (sut, _, _) = try AttestFixture.makeService()

        do {
            _ = try await sut.attest(entry: "myEntry")
            XCTFail("expected the attestation to fail")
        } catch {
            let host = try XCTUnwrap(TapToPayErrorTranslation.hostError(for: error) as? TapToPayError)
            XCTAssertEqual(host.type, .serverError)
            XCTAssertEqual(host.httpStatus, 200)
        }
    }

    func testAConfigRefusalOfTheEntryPointUnderA400IsTheEntryPointRefused() async throws {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!,
                Self.decline(code: 403, reason: ColdRouteRefusals.entryPointUnusable)
            )
        }
        let ttp = try makeTTP()

        do {
            try await ttp.initialize()
            XCTFail("expected initialize to fail")
        } catch let error as TapToPayError {
            XCTAssertEqual(error.type, .entryPointRefused, "an activation code cannot resolve this refusal")
        }
    }

    func testAConfigSuccessCarryingNoCredentialsIsADecodingFailure() async throws {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                Data(#"{"isSuccess":true,"responseCode":1,"responseData":{}}"#.utf8)
            )
        }
        let ttp = try makeTTP()

        do {
            try await ttp.initialize()
            XCTFail("expected initialize to fail")
        } catch let error as TapToPayError {
            XCTAssertEqual(error.type, .decodingError)
            XCTAssertEqual(error.code, 1014)
        }
        XCTAssertEqual(ttp.sessionState, .failed(reason: .sdkInternalError))
    }

    func testARepairWithNoBindingStoredAsksForSetup() async throws {
        let (sut, _, _) = try AttestFixture.makeService()

        do {
            _ = try await sut.generateAssertion(for: "myEntry")
            XCTFail("expected the assertion to fail")
        } catch {
            let host = try XCTUnwrap(TapToPayErrorTranslation.hostError(for: error) as? TapToPayError)
            XCTAssertEqual(host.code, 3005)
            XCTAssertEqual(
                PayabliTTPSessionState.landing(for: error, registration: .none),
                .failed(reason: .deviceSetupRequired)
            )
        }
    }

    // MARK: - Fixtures

    /// The host error `/challenge` lands on when it answers `status` with `body`.
    private func attestFailure(status: Int, body: Data) async throws -> TapToPayError {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, body)
        }
        let (sut, _, _) = try AttestFixture.makeService()
        do {
            _ = try await sut.attest(entry: "myEntry")
        } catch {
            return try XCTUnwrap(TapToPayErrorTranslation.hostError(for: error) as? TapToPayError)
        }
        XCTFail("expected the attestation to fail")
        throw CancellationError()
    }

    private static func decline(code: Int) -> Data {
        decline(code: code, reason: "REASON-SENTINEL")
    }

    private static func decline(code: Int?, reason: String) -> Data {
        let resultCode = code.map { #""resultCode":\#($0),"# } ?? ""
        return Data(#"{"isSuccess":false,"responseData":{\#(resultCode)"resultText":"\#(reason)"}}"#.utf8)
    }

    private func makeTTP() throws -> PayabliTTP {
        PayabliTTP(
            config: try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
            provider: MockTapToPayProvider(),
            attestation: MockDeviceAttestationService(),
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
    }
}
