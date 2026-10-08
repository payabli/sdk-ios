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

    /// A setup whose owner withdrew sent nothing, so asking again is safe.
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
