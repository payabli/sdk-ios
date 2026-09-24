@testable import PayabliSDKTapToPay
import XCTest

#if canImport(PayabliCardReaderCore) && canImport(ProximityReader)
    import PayabliCardReaderCore
    import ProximityReader

    /// What `mapError` does with the errors it actually receives.
    ///
    /// The card-reader component's throwing methods only ever throw their own
    /// type, so the platform's error arrives rebuilt as a title, a description
    /// and the error it was built from. These tests assert against that shape
    /// rather than against a raw `PaymentCardReaderError`, because the raw one
    /// never arrives.
    final class FiservCardReaderErrorMappingTests: XCTestCase {
        // MARK: - Pass-through

        func testAnErrorThatIsAlreadyOursIsForwarded() {
            let mapped = FiservCardReader.mapError(PayabliTTPError.tokenExpired) { .nfcFailed(reason: $0) }

            guard case .tokenExpired = mapped else {
                return XCTFail("expected .tokenExpired, got \(mapped)")
            }
        }

        // MARK: - Recognised from the type

        /// A host shows this differently from a transient failure, so it is its
        /// own case rather than a reason string the host has to read.
        func testAnUnsupportedOSVersionIsItsOwnCase() {
            let mapped = FiservCardReader.mapError(Self.rebuilt(.osVersionNotSupported)) {
                .readerSetupFailed(reason: $0)
            }

            guard case .readerOSVersionNotSupported = mapped else {
                return XCTFail("expected .readerOSVersionNotSupported(), got \(mapped)")
            }
        }

        /// The description is localized and the platform does not promise its
        /// wording, so a reader error whose text happens to say "version" is
        /// not an unsupported OS version.
        func testAnotherFailureIsNotMistakenForAVersionProblem() {
            let mapped = FiservCardReader.mapError(Self.rebuilt(.notReady)) { .readerSetupFailed(reason: $0) }

            guard case .readerSetupFailed = mapped else {
                return XCTFail("expected .readerSetupFailed, got \(mapped)")
            }
        }

        func testACancelledReadCarriesTheCancellationPrefix() {
            let mapped = FiservCardReader.mapError(Self.rebuiltRead(.readCancelled)) { .nfcFailed(reason: $0) }

            guard case let .nfcFailed(reason, _) = mapped else {
                return XCTFail("expected .nfcFailed, got \(mapped)")
            }
            XCTAssertTrue(reason.hasPrefix(FiservCardReader.cancellationReasonPrefix), reason)
        }

        func testAFailedReadIsNotACancellation() {
            let mapped = FiservCardReader.mapError(Self.rebuiltRead(.cardReadFailed)) { .nfcFailed(reason: $0) }

            guard case let .nfcFailed(reason, _) = mapped else {
                return XCTFail("expected .nfcFailed, got \(mapped)")
            }
            XCTAssertFalse(reason.hasPrefix(FiservCardReader.cancellationReasonPrefix), reason)
        }

        // MARK: - The unrecognised path

        func testAnUnrecognisedReaderErrorKeepsTheTitleAndTheDescription() {
            let mapped = FiservCardReader.mapError(Self.rebuilt(.readerBusy)) { .readerSetupFailed(reason: $0) }

            guard case let .readerSetupFailed(reason, _) = mapped else {
                return XCTFail("expected .readerSetupFailed, got \(mapped)")
            }
            XCTAssertEqual(
                reason,
                "\(PaymentCardReaderError.readerBusy.errorName): \(PaymentCardReaderError.readerBusy.errorDescription)"
            )
        }

        func testTheFallbackPicksTheCase() {
            let mapped = FiservCardReader.mapError(Self.rebuilt(.readerBusy)) { .nfcFailed(reason: $0) }

            guard case .nfcFailed = mapped else {
                return XCTFail("expected .nfcFailed, got \(mapped)")
            }
        }

        /// A reader error carrying no platform error still reports, by its own
        /// two strings. That is what a failure the component raised itself
        /// looks like, and what an older copy of it produced for everything.
        func testAReaderErrorWithNoPlatformErrorStillReports() {
            let mapped = FiservCardReader.mapError(
                FiservTTPCardReaderError(title: "Missing Token", localizedDescription: "a token is required")
            ) { .readerSetupFailed(reason: $0) }

            guard case let .readerSetupFailed(reason, _) = mapped else {
                return XCTFail("expected .readerSetupFailed, got \(mapped)")
            }
            XCTAssertEqual(reason, "Missing Token: a token is required")
        }

        func testAnErrorFromNowhereNearTheReaderFallsBackToItsDescription() {
            struct Opaque: Error {}

            let mapped = FiservCardReader.mapError(Opaque()) { .readerSetupFailed(reason: $0) }

            guard case let .readerSetupFailed(reason, _) = mapped else {
                return XCTFail("expected .readerSetupFailed, got \(mapped)")
            }
            XCTAssertFalse(reason.isEmpty)
        }

        // MARK: - Fixtures

        /// Built the way `FiservTTPReader` builds it: the platform's own
        /// `errorName` and `errorDescription`, and the error itself.
        private static func rebuilt(_ error: PaymentCardReaderError) -> FiservTTPCardReaderError {
            FiservTTPCardReaderError(
                title: error.errorName,
                localizedDescription: error.errorDescription,
                underlying: error
            )
        }

        private static func rebuiltRead(_ error: PaymentCardReaderSession.ReadError) -> FiservTTPCardReaderError {
            FiservTTPCardReaderError(
                title: error.errorName,
                localizedDescription: error.errorDescription,
                underlying: error
            )
        }
    }

#endif
