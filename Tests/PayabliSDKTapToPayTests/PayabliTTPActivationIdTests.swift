import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

@MainActor
final class PayabliTTPActivationIdTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeTTP(
        attestation: MockDeviceAttestationService = MockDeviceAttestationService()
    ) throws -> (PayabliTTP, MockDeviceAttestationService) {
        let config = try PayabliConfig(
            entryPoint: "e",
            environment: .sandbox,
            tokenProvider: { "seed_token" }
        )
        let ttp = PayabliTTP(
            config: config,
            provider: MockTapToPayProvider(),
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        return (ttp, attestation)
    }

    private static func respond(_ status: Int) -> StubURLProtocol.Handler {
        { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("{}".utf8)
            )
        }
    }

    func testARegistrationLeftPendingHandsOverItsId() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev_e"

        do {
            try await ttp.initialize()
            XCTFail("expected pending activation")
        } catch PayabliTTPError.devicePendingActivation {}

        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_e"))
    }

    func testAnEnrolledDeviceTheServiceStillHoldsPendingHandsOverItsBoundId() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.bindings = ["e": "dev_e"]
        StubURLProtocol.handler = Self.respond(403)

        _ = try? await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_e"))
    }

    func testInitializingAgainLandsOnTheSameId() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev_e"
        _ = try? await ttp.initialize()
        attestation.pendingRegistration = nil
        StubURLProtocol.handler = Self.respond(403)

        _ = try? await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_e"))
    }

    /// With nothing registered there is no device to activate, so the remedy is the paypoint's. The
    /// error still names the refusal that happened.
    func testARefusalBeforeAnyRegistrationIsNotPendingActivation() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.attestResult = .failure(
            PayabliGenericError(type: .permissionDenied, reason: "Forbidden (403)")
        )

        do {
            try await ttp.initialize()
            XCTFail("expected the refusal")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.type, .permissionDenied)
        }

        XCTAssertEqual(ttp.sessionState, .failed(reason: .configurationRejected))
    }

    func testPendingWithAStoreThatCannotBeReadThrowsWhatTheSessionLandsOn() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev_e"
        attestation.registrationReadFailure = PayabliTTPError.attestationFailed(reason: "unreadable")

        do {
            try await ttp.initialize()
            XCTFail("expected a failure")
        } catch let error as TapToPayError {
            XCTAssertEqual(error.type, .deviceKeyUnavailable)
        }

        XCTAssertEqual(ttp.sessionState, .failed(reason: .deviceKeyUnavailable))
    }

    func testTheObjCReaderAnswersOnlyWhileActivationIsOwed() async throws {
        let (ttp, attestation) = try makeTTP()
        XCTAssertNil(ttp.activationId)

        attestation.pendingRegistration = "dev_e"
        _ = try? await ttp.initialize()

        XCTAssertEqual(ttp.activationId, "dev_e")

        try await ttp.activateDevice(activationCode: "ABC123")

        XCTAssertNil(ttp.activationId)
    }
}
