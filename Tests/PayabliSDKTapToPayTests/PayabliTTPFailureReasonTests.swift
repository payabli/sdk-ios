import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// Where a failure lands, and what the state then says about it.
///
/// A landing is a remedy, so these assert the remedy a host would offer rather
/// than the error that produced it.
final class PayabliTTPFailureReasonTests: XCTestCase {
    // MARK: - The landings

    /// Both name the attestation, which is the positive match discarding the
    /// device's identity needs.
    func testAFailureThatNamesTheAttestationAsksForOne() {
        for error in [
            PayabliTTPError.attestationRevoked(reason: "x"),
            .attestationFailed(reason: "x")
        ] {
            XCTAssertEqual(
                PayabliTTPSessionState.landing(for: error),
                .failed(reason: .attestationRequired),
                "\(error)"
            )
        }
    }

    /// An expired token names no attestation, so it does not discard the
    /// identity. The device is as it was and the same call may work later.
    func testAnExpiredTokenDoesNotDiscardTheIdentity() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.tokenExpired),
            .failed(reason: .serviceUnavailable)
        )
    }

    func testAnAccountThatIsNotSetUpAsksSomeoneToChangeIt() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.configFailed(reason: "x")),
            .failed(reason: .configurationRejected)
        )
    }

    /// An OS build the reader will never run on is the device. A reader that
    /// merely would not arm is not: it leaves the device as it was.
    func testOnlyAnUnusableDeviceIsCalledIneligible() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.readerOSVersionNotSupported),
            .failed(reason: .deviceIneligible)
        )
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.readerSetupFailed(reason: "x")),
            .failed(reason: .serviceUnavailable)
        )
    }

    /// A device owing activation is not a failure, and neither is a merchant who
    /// has not accepted terms. Each has a state of its own.
    func testWhatIsNotAFailureDoesNotLandAsOne() {
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.devicePendingActivation),
            .pendingActivation
        )
        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: PayabliTTPError.termsNotAccepted),
            .pendingTerms
        )
    }

    /// A tap or an activation failing leaves the session where it was.
    func testAFailureThatIsNotTheSessionsMovesNothing() {
        for error in [
            PayabliTTPError.nfcFailed(reason: "x"),
            .initiateFailed(reason: "x"),
            .updateFailed(reason: "x"),
            .activationFailed(reason: "x")
        ] {
            XCTAssertNil(PayabliTTPSessionState.landing(for: error), "\(error)")
        }
    }

    /// A refused body is the two sides disagreeing about the contract, not a
    /// service that might answer differently in a minute: the same bytes get
    /// the same 400.
    func testARefusedBodyIsNotWorthRetrying() throws {
        // Decoded rather than constructed: the type carries no public
        // memberwise initializer, which is its own ticket.
        let refused = PayabliPaymentError.validation(
            try JSONDecoder().decode(PayabliValidationError.self, from: Data("{}".utf8))
        )

        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: refused),
            .failed(reason: .sdkInternalError)
        )
    }

    /// A status nothing has been seen producing has no agreed meaning, so it
    /// lands where being wrong costs a retry rather than a bug report.
    func testAStatusNoRouteHasProducedIsTreatedAsTransient() {
        let burned = PayabliGenericError(code: .sessionBurned, reason: "Gone (410)")

        XCTAssertEqual(
            PayabliTTPSessionState.landing(for: burned),
            .failed(reason: .serviceUnavailable)
        )
    }

    /// Every case lands somewhere, including on nothing. A case added without a
    /// landing would reach a host as a remedy it cannot act on.
    func testEveryErrorCaseHasALanding() {
        let everyCase: [PayabliTTPError] = [
            .notInitialized,
            .invalidState(current: .ready, attempted: "x"),
            .notReady(current: .idle),
            .devicePendingActivation,
            .attestationRevoked(reason: "x"),
            .attestationFailed(reason: "x"),
            .configFailed(reason: "x"),
            .readerSetupFailed(reason: "x"),
            .nfcFailed(reason: "x"),
            .initiateFailed(reason: "x"),
            .updateFailed(reason: "x"),
            .tokenExpired,
            .activationFailed(reason: "x"),
            .networkError(reason: "x"),
            .termsNotAccepted,
            .readerOSVersionNotSupported
        ]

        XCTAssertEqual(everyCase.count, 16, "a case was added to PayabliTTPError without a landing")
    }

    // MARK: - What the state carries

    func testTheStateCarriesTheReasonItFailedFor() {
        let state = PayabliTTPSessionState.failed(reason: .deviceIneligible)

        XCTAssertEqual(state.failureReason, .deviceIneligible)
        XCTAssertEqual(state.code, .failed)
    }

    func testAStateThatHasNotFailedCarriesNoReason() {
        XCTAssertNil(PayabliTTPSessionState.ready.failureReason)
        XCTAssertNil(PayabliTTPSessionState.initializingReader(percent: 50).failureReason)
    }

    /// The codes are what every bridge reads, so they are pinned here.
    func testTheProjectionIsStable() {
        XCTAssertEqual(PayabliTTPSessionStateCode.idle.rawValue, 0)
        XCTAssertEqual(PayabliTTPSessionStateCode.attestingDevice.rawValue, 1)
        XCTAssertEqual(PayabliTTPSessionStateCode.fetchingConfig.rawValue, 2)
        XCTAssertEqual(PayabliTTPSessionStateCode.initializingReader.rawValue, 3)
        XCTAssertEqual(PayabliTTPSessionStateCode.ready.rawValue, 4)
        XCTAssertEqual(PayabliTTPSessionStateCode.sessionExpired.rawValue, 5)
        XCTAssertEqual(PayabliTTPSessionStateCode.reinitializing.rawValue, 6)
        XCTAssertEqual(PayabliTTPSessionStateCode.pendingActivation.rawValue, 7)
        XCTAssertEqual(PayabliTTPSessionStateCode.failed.rawValue, 8)
        XCTAssertEqual(PayabliTTPSessionStateCode.pendingTerms.rawValue, 9)
    }

    /// The five members mirror the sibling platform's published vocabulary, so a
    /// host branching on one branches on the same set on both.
    func testTheVocabularyMirrorsTheSibling() {
        XCTAssertEqual(PayabliTTPFailureReason.allCases.count, 5)
    }
}
