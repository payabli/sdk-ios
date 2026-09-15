import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// Where a failure lands, and what the state then says about it.
///
/// A landing is a remedy, so these assert the remedy a host would offer rather
/// than the error that produced it.
final class PayabliTTPFailureReasonTests: XCTestCase {
    // MARK: - The landings

    func testAStaleIdentityAsksForAttestation() {
        for error in [
            PayabliTTPError.attestationRevoked(reason: "x"),
            .attestationFailed(reason: "x"),
            .tokenExpired
        ] {
            XCTAssertEqual(PayabliTTPFailureReason.landing(for: error), .attestationRequired, "\(error)")
        }
    }

    func testAnAccountThatIsNotSetUpAsksSomeoneToChangeIt() {
        XCTAssertEqual(
            PayabliTTPFailureReason.landing(for: PayabliTTPError.configFailed(reason: "x")),
            .configurationRejected
        )
    }

    /// The hardware, the OS build and a vendor refusal arrive alike, and a host
    /// offers the same thing for all three.
    func testAReaderThatWillNotComeUpIsTheDevice() {
        for error in [
            PayabliTTPError.readerSetupFailed(reason: "x"),
            .readerOSVersionNotSupported
        ] {
            XCTAssertEqual(PayabliTTPFailureReason.landing(for: error), .deviceIneligible, "\(error)")
        }
    }

    func testAServiceThatCouldNotBeReachedMayWorkLater() {
        XCTAssertEqual(
            PayabliTTPFailureReason.landing(for: PayabliTTPError.networkError(reason: "x")),
            .serviceUnavailable
        )
    }

    /// A guess sends a host down a repair that cannot work, so anything whose
    /// remedy is unknown lands where being wrong costs nothing.
    func testAnUnrecognisedFailureAsksForADefectReport() {
        struct Opaque: Error {}

        XCTAssertEqual(PayabliTTPFailureReason.landing(for: Opaque()), .sdkInternalError)
        XCTAssertEqual(
            PayabliTTPFailureReason.landing(for: PayabliTTPError.notInitialized),
            .sdkInternalError
        )
    }

    /// Every case lands somewhere. A new one added to `PayabliTTPError` without a
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

        for error in everyCase {
            XCTAssertNotNil(PayabliTTPFailureReason.landing(for: error), "\(error)")
        }
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
