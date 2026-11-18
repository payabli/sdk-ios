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
                XCTAssertEqual(host.rawCode, String(row.code!))
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

    private static func decline(code: Int) -> Data {
        Data(#"{"isSuccess":false,"responseData":{"resultCode":\#(code),"resultText":"REASON-SENTINEL"}}"#.utf8)
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
