@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// A device or activation refusal reaches a host carrying the refusing answer's status and no code, and an answer the
/// SDK cannot read carries its status.
final class DeviceRefusalStatusTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Refusals

    func testAnEntryPointRefusedOnRegisterCarriesItsStatus() async throws {
        stubColdRoutes(refusing: Self.register, status: 403, text: "Entry point is not available for this request.")

        let host = try await attestFailure()

        XCTAssertEqual(host.type, .entryPointRefused)
        XCTAssertEqual(host.httpStatus, 403)
        XCTAssertNil(host.rawCode)
    }

    func testADeviceTheServiceDoesNotKnowOnAttestCarriesItsStatus() async throws {
        stubColdRoutes(refusing: Self.attest, status: 404, text: "Device not found.")

        let host = try await attestFailure()

        XCTAssertEqual(host.type, .deviceSetupRequired)
        XCTAssertEqual(host.httpStatus, 404)
        XCTAssertNil(host.rawCode)
    }

    func testARefusedAttestationCarriesItsStatus() async throws {
        stubColdRoutes(refusing: Self.attest, status: 400, text: "Attestation verification failed: bad nonce")

        let host = try await attestFailure()

        XCTAssertEqual(host.httpStatus, 400)
        XCTAssertNil(host.rawCode)
    }

    func testAnAppThePaypointHasNotRegisteredCarriesItsStatus() async throws {
        stubColdRoutes(refusing: Self.register, status: 403, text: "Application is not authorized for this paypoint.")

        let host = try await attestFailure()

        XCTAssertEqual(host.type, .deviceSetupNotConfigured)
        XCTAssertEqual(host.httpStatus, 403)
        XCTAssertNil(host.rawCode)
    }

    func testADeclineOnASuccessStatusCarriesThatStatus() async throws {
        stubColdRoutes(refusing: Self.attest, status: 200, text: "Something the SDK does not classify")

        let host = try await attestFailure()

        XCTAssertEqual(host.httpStatus, 200)
        XCTAssertNil(host.rawCode)
    }

    func testARefusedActivationCodeCarriesItsStatus() async throws {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!,
                Self.refusalBody(status: 400, text: "Invalid activation code.")
            )
        }
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
        let (sut, _, _) = try AttestFixture.makeService(storage: storage)

        let host: TapToPayError
        do {
            try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev")
            return XCTFail("the activation was accepted")
        } catch {
            host = try XCTUnwrap(TapToPayErrorTranslation.hostError(for: error) as? TapToPayError, "\(error)")
        }

        XCTAssertEqual(host.type, .activationCodeIncorrect)
        XCTAssertEqual(host.httpStatus, 400)
        XCTAssertNil(host.rawCode)
    }

    // MARK: - The challenge

    func testAChallengeThatIsNotBase64IsRefusedBeforeAKeyIsMadeOrSpent() async throws {
        let paths = PathsBox()
        StubURLProtocol.handler = { request in
            paths.append(request.url!.path)
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "not base64!"])
        }
        let (sut, attestor, _) = try AttestFixture.makeService()

        let host = try await attestFailure(sut)

        XCTAssertEqual(host.type, .decodingError)
        XCTAssertEqual(host.httpStatus, 200)
        XCTAssertNil(host.rawCode)
        XCTAssertEqual(paths.values, [Self.challenge], "nothing is sent after the challenge")
        XCTAssertEqual(attestor.generateKeyCalls, 0)
        XCTAssertEqual(attestor.attestKeyCalls, 0)
    }

    func testAChallengeAnswerWithNoPayloadCarriesItsStatus() async throws {
        StubURLProtocol.handler = { request in
            let body = try! JSONSerialization.data(withJSONObject: ["isSuccess": true, "responseText": "OK"])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!, body)
        }
        let (sut, _, _) = try AttestFixture.makeService()

        let host = try await attestFailure(sut)

        XCTAssertEqual(host.type, .decodingError)
        XCTAssertEqual(host.httpStatus, 200)
    }

    // MARK: - Fixtures

    private static let challenge = "/api/v2/device/taptopay/challenge"
    private static let register = "/api/v2/device/taptopay/register"
    private static let attest = "/api/v2/device/taptopay/attest"

    private func attestFailure(_ given: AppAttestService? = nil) async throws -> TapToPayError {
        let sut = try given ?? AttestFixture.makeService().0
        do {
            _ = try await sut.attest(entry: "myEntry")
        } catch {
            return try XCTUnwrap(TapToPayErrorTranslation.hostError(for: error) as? TapToPayError, "\(error)")
        }
        XCTFail("the attestation finished")
        throw CancellationError()
    }

    /// Answers the refused route with its status and words, `/challenge` with a base64 challenge, and every other route
    /// with a device id.
    private func stubColdRoutes(refusing refusedPath: String, status: Int, text: String) {
        StubURLProtocol.handler = { request in
            let path = request.url!.path
            if path == refusedPath {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.refusalBody(status: status, text: text)
                )
            }
            if path == Self.challenge {
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            }
            return AttestFixture.ok(request, ["deviceId": "dev_1"])
        }
    }

    /// The legacy envelope every device route refuses in: the status as the result code, the words as the result text.
    private static func refusalBody(status: Int, text: String) -> Data {
        let payload: [String: Any] = [
            "isSuccess": false,
            "responseData": ["resultCode": status, "resultText": text]
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}
