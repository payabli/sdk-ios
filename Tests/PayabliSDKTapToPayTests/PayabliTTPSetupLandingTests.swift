@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// Where `initialize` leaves the session when setting the device up fails, read through the facade a
/// host calls.
@MainActor
final class PayabliTTPSetupLandingTests: XCTestCase {
    /// Each way setting the device up fails reaches the state its remedy repairs, and none of them
    /// asks for the device to be set up again.
    func testAFailedSetupLandsWhereItsRemedyRepairsIt() async throws {
        let cases: [(PayabliErrorType, PayabliTTPSessionState)] = [
            (.deviceKeyUnavailable, .failed(reason: .deviceKeyUnavailable)),
            (.sdkInternalError, .failed(reason: .sdkInternalError)),
            (.decodingError, .failed(reason: .sdkInternalError)),
            (.deviceSetupUnavailable, .failed(reason: .serviceUnavailable)),
            (.deviceSetupUnsupported, .failed(reason: .deviceIneligible)),
            (.deviceSetupNotConfigured, .failed(reason: .configurationRejected)),
            (.deviceIdentityUnavailable, .failed(reason: .deviceIneligible))
        ]
        for (type, expected) in cases {
            let (ttp, _, attestation) = try makeTTP()
            attestation.attestResult = .failure(TapToPayError(type: type, reason: "x", detail: nil))

            do {
                try await ttp.initialize()
                XCTFail("initialize proceeded past \(type)")
            } catch {
                XCTAssertEqual((error as? TapToPayError)?.type, type, "\(error)")
            }
            XCTAssertEqual(ttp.sessionState, expected, "\(type)")
        }
    }

    /// A withdrawn setup is asked again, which is safe.
    func testAWithdrawnSetupLandsOnIdle() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.attestResult = .failure(CancellationError())

        do {
            try await ttp.initialize()
            XCTFail("initialize proceeded past a withdrawn setup")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(ttp.sessionState, .idle)
    }

    /// A device the service no longer recognises during activation is set up again, the same answer
    /// `initialize` gives.
    func testActivationRefusedForASetupThatEndedLandsOnDeviceSetupRequired() async throws {
        let failures: [Error] = [
            PayabliTTPError.attestationRevoked(reason: "x"),
            ActivationRegistrationChanged()
        ]
        for failure in failures {
            let (ttp, _, attestation) = try makeTTP()
            attestation.pendingRegistration = "dev_e"
            _ = try? await ttp.initialize()
            XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_e"), "\(failure)")
            attestation.activationResult = .failure(failure)

            do {
                try await ttp.activateDevice(activationCode: "123456")
                XCTFail("activation succeeded past \(failure)")
            } catch {
                XCTAssertEqual((error as? TapToPayError)?.type, .deviceSetupRequired, "\(failure): \(error)")
            }
            XCTAssertEqual(ttp.sessionState, .failed(reason: .deviceSetupRequired), "\(failure)")
        }
    }

    private func makeTTP() throws -> (PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService) {
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" })
        let provider = MockTapToPayProvider()
        let attestation = MockDeviceAttestationService()
        let ttp = PayabliTTP(
            config: config,
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        return (ttp, provider, attestation)
    }
}
