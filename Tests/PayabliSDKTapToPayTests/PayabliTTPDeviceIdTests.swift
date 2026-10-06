import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

@MainActor
final class PayabliTTPDeviceIdTests: XCTestCase {
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

    func testNoBindingAnswersNil() async throws {
        let (ttp, _) = try makeTTP()

        let deviceId = await ttp.deviceId()

        XCTAssertNil(deviceId)
    }

    func testAnswersTheIdBoundToThisEntryPointAndNoOther() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.bindings = ["other": "dev_other", "e": "dev_e"]

        let deviceId = await ttp.deviceId()

        XCTAssertEqual(deviceId, "dev_e")
    }

    func testABindingForAnotherEntryPointOnlyAnswersNil() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.bindings = ["other": "dev_other"]

        let deviceId = await ttp.deviceId()

        XCTAssertNil(deviceId)
    }

    /// The moment a host needs the id is while the device waits for its code.
    func testAnswersTheIdWhileTheDeviceIsPendingActivation() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.attestResult = .failure(PayabliTTPError.devicePendingActivation)
        _ = try? await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .pendingActivation)
        // Registration stores the binding before the service reports the device pending.
        attestation.bindings = ["e": "dev_e"]

        let deviceId = await ttp.deviceId()

        XCTAssertEqual(deviceId, "dev_e")
    }

    func testAStoreThatCannotBeReadAnswersNilRatherThanThrowing() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.bindings = ["e": "dev_e"]
        attestation.readFailure = PayabliTTPError.attestationFailed(reason: "unreadable")

        let deviceId = await ttp.deviceId()

        XCTAssertNil(deviceId)
    }

    func testABindingWhoseKeyIsGoneAnswersNil() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.bindings = ["e": "dev_e"]
        attestation.heldKeyIsGone = true

        let deviceId = await ttp.deviceId()

        XCTAssertNil(deviceId)
    }

    func testTheObjCCompanionDeliversTheId() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.bindings = ["e": "dev_e"]

        let done = expectation(description: "completion")
        ttp.deviceId { deviceId in
            XCTAssertEqual(deviceId, "dev_e")
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 1)
    }
}
