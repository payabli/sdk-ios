import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

// MARK: - A retry refused before its key is reserved

@available(iOS 16.7, *)
extension TTPChargeKeyTests {
    func testARetryRefusedAsNotReadyWhileItsSaleIsHeldStaysUnknownAndKeepsTheKey() async throws {
        let (ttp, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        let ready = waitOnActivation(ttp)

        let refused = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(refused?.type, .terminalNotReady)
        XCTAssertEqual(refused?.capture, .unknown)
        XCTAssertEqual(Self.wire.keys.count, 1, "the refused retry sent its opening")
        ready()
        provider.readingResult = Self.read(.approved)
        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)
        XCTAssertEqual(Self.wire.keys[1], Self.wire.keys[0], "the refusal let the held key go")
    }

    func testARetryRefusedForAMissingDeviceWhileItsSaleIsHeldStaysUnknownAndKeepsTheKey() async throws {
        let attestation = MockDeviceAttestationService()
        let (ttp, provider) = try await makeReadyTTP(outcome: .indeterminate, attestation: attestation)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        let deviceId = attestation.cachedDeviceId
        attestation.cachedDeviceId = nil

        let refused = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(refused?.type, .deviceSetupRequired)
        XCTAssertEqual(refused?.capture, .unknown)
        XCTAssertEqual(Self.wire.keys.count, 1, "the refused retry sent its opening")
        attestation.cachedDeviceId = deviceId
        provider.readingResult = Self.read(.approved)
        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)
        XCTAssertEqual(Self.wire.keys[1], Self.wire.keys[0], "the refusal let the held key go")
    }

    func testARetryRefusedBeforeItsKeyWithNothingHeldIsNotCharged() async throws {
        let (ttp, _) = try await makeReadyTTP()
        _ = waitOnActivation(ttp)

        let refused = await failure { try await ttp.charge(paymentDetails: Self.details, attempt: .retry) }

        XCTAssertEqual(refused?.type, .terminalNotReady)
        XCTAssertEqual(refused?.capture, .notCharged)
    }

    func testARetryRefusedBeforeItsKeyForAnotherSaleIsNotCharged() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        _ = waitOnActivation(ttp)

        let refused = await failure {
            try await ttp.charge(paymentDetails: PayabliTTPPaymentDetails(amount: 2, currency: "USD"), attempt: .retry)
        }

        XCTAssertEqual(refused?.type, .terminalNotReady)
        XCTAssertEqual(refused?.capture, .notCharged)
    }

    func testANewPaymentRefusedBeforeItsKeyWhileTheSameSaleIsHeldIsNotCharged() async throws {
        let (ttp, _) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await failure { try await ttp.charge(paymentDetails: Self.details) }
        _ = waitOnActivation(ttp)

        let refused = await failure { try await ttp.charge(paymentDetails: Self.details) }

        XCTAssertEqual(refused?.type, .terminalNotReady)
        XCTAssertEqual(refused?.capture, .notCharged)
    }

    /// Leaves the session waiting on activation, a state a charge is refused in before it reserves a key.
    ///
    /// - Parameter ttp: the terminal, ready.
    /// - Returns: puts the terminal back to ready.
    private func waitOnActivation(_ ttp: PayabliTTP) -> () -> Void {
        for state: PayabliTTPSessionState in [.idle, .attestingDevice, .pendingActivation(activationId: "activation")] {
            XCTAssertTrue(ttp.sessionManager.transition(to: state), "the fixture itself is broken if this fails")
        }
        ttp.syncPublished()
        return {
            let setUp: [PayabliTTPSessionState] = [.attestingDevice, .fetchingConfig, .initializingReader(percent: nil), .ready]
            for state in setUp {
                XCTAssertTrue(ttp.sessionManager.transition(to: state), "the fixture itself is broken if this fails")
            }
            ttp.syncPublished()
        }
    }
}
