@testable import PayabliSDKTapToPay
import XCTest

#if canImport(PayabliCardReaderCore) && canImport(ProximityReader)
    @testable import PayabliCardReaderCore
    import ProximityReader

    /// What `mapError` does with the errors it actually receives.
    ///
    /// The card-reader component's throwing methods only ever throw their own
    /// type, so the platform's error arrives rebuilt as a title, a description
    /// and the error it was built from. These tests assert against that shape
    /// rather than against a raw `PaymentCardReaderError`, because the raw one
    /// never arrives.
    @available(iOS 16.7, *)
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

        /// A read that finds the reader session spent is the session's expiry, and the processor may have taken
        /// the sale before the reader answered.
        func testAReadThatFindsTheSessionSpentIsTheSessionsExpiry() {
            for error in [Self.rebuiltRead(.readerSessionExpired), Self.rebuiltRead(.noReaderSession)] {
                guard case let .readerSessionExpired(_, capture) = FiservCardReader.mapReadError(error) else {
                    return XCTFail("expected .readerSessionExpired for \(error)")
                }
                XCTAssertEqual(capture, .unknown)
            }
        }

        /// The card reader refuses to read without a session before any card is asked for, so nothing was charged.
        func testAReadRefusedForWantOfASessionIsTheSessionsExpiryAndChargesNothing() {
            let refusal = FiservTTPCardReaderError(
                title: FiservCardReader.noSessionRefusal.title,
                localizedDescription: FiservCardReader.noSessionRefusal.description
            )

            for error in [refusal, Self.chargeFailure(behind: refusal)] {
                guard case let .readerSessionExpired(_, capture) = FiservCardReader.mapReadError(error) else {
                    return XCTFail("expected .readerSessionExpired for \(error)")
                }
                XCTAssertEqual(capture, .notCharged)
            }
        }

        /// The charge's own failure reads the same for every refusal behind it, so only the one it keeps decides.
        func testAnUnreadableCardBehindTheChargesFailureStaysAnNFCFailure() {
            let unreadable = FiservTTPCardReaderError(
                title: "Read Payment Card",
                localizedDescription: "The card was unable to be successfully read."
            )

            guard case .nfcFailed = FiservCardReader.mapReadError(Self.chargeFailure(behind: unreadable)) else {
                return XCTFail("expected .nfcFailed")
            }
        }

        /// The card reader's own refusal is the text the mapping matches, so a reworded refusal fails here.
        func testTheCardReadersRefusalWithoutASessionIsTheOneMatched() async throws {
            let reader = FiservTTPReader(config: FiservTTPConfig(
                secretKey: "s", apiKey: "a", environment: .Sandbox, currencyCode: "USD", merchantId: "m",
                merchantName: "n", merchantCategoryCode: "5999", terminalId: "t", terminalProfileId: "p"
            ))

            let result = try await reader.readCard(for: 1, currencyCode: "USD", transactionType: .purchase)

            guard case let .failure(refusal) = result else { return XCTFail("expected the read to be refused") }
            XCTAssertTrue(FiservCardReader.refusedToReadWithoutASession(Self.chargeFailure(behind: refusal)))
        }

        /// Where the platform's type did not survive, its case name in the reader's words still says so.
        func testASpentSessionNamedOnlyInTheReadersWordsIsTheSessionsExpiry() {
            let named = FiservTTPCardReaderError(title: "readerTokenExpired", localizedDescription: "token expired")

            guard case .readerSessionExpired = FiservCardReader.mapReadError(named) else {
                return XCTFail("expected .readerSessionExpired")
            }
        }

        /// A read that failed while the session lives keeps the read's own case.
        func testAReadFailureTheSessionSurvivesIsNotAnExpiry() {
            guard case .nfcFailed = FiservCardReader.mapReadError(Self.rebuiltRead(.cardReadFailed)) else {
                return XCTFail("expected .nfcFailed")
            }
        }

        func testACancelledReadCarriesTheCancellationPrefix() {
            let mapped = FiservCardReader.mapError(Self.rebuiltRead(.readCancelled)) { .nfcFailed(reason: $0) }

            guard case let .nfcFailed(reason, _) = mapped else {
                return XCTFail("expected .nfcFailed, got \(mapped)")
            }
            XCTAssertTrue(reason.hasPrefix(PayabliTTPError.cancellationReasonPrefix), reason)
        }

        func testAFailedReadIsNotACancellation() {
            let mapped = FiservCardReader.mapError(Self.rebuiltRead(.cardReadFailed)) { .nfcFailed(reason: $0) }

            guard case let .nfcFailed(reason, _) = mapped else {
                return XCTFail("expected .nfcFailed, got \(mapped)")
            }
            XCTAssertFalse(reason.hasPrefix(PayabliTTPError.cancellationReasonPrefix), reason)
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

        // MARK: - The vendor's own answer

        /// The vendor's record of refusing the handset, carried in its failure
        /// reason, reports the refusal's own case rather than the setup failure's.
        func testAVendorDenialOfTheDeviceReportsTheDevicesRefusal() {
            let mapped = FiservCardReader.mapError(Self.vendorDenied) { .readerSetupFailed(reason: $0) }

            let host = TapToPayErrorTranslation.hostError(for: mapped)
            XCTAssertEqual((host as? TapToPayError)?.type, .readerDeviceRefused, "\(mapped)")
        }

        /// A vendor failure that is not a denial of the handset reports the
        /// reader's own case.
        func testAVendorFailureOfTheReaderReportsTheReadersOwnCase() {
            let mapped = FiservCardReader.mapError(Self.vendorFailed) { .readerSetupFailed(reason: $0) }

            let host = TapToPayErrorTranslation.hostError(for: mapped)
            XCTAssertEqual((host as? TapToPayError)?.type, .readerUnavailable, "\(mapped)")
        }

        /// A denial carried in the server error envelope's `error` list reports the refusal's own case.
        func testAVendorDenialInTheErrorListReportsTheDevicesRefusal() {
            let mapped = FiservCardReader.mapError(Self.vendorDeniedInErrorList) { .readerSetupFailed(reason: $0) }

            let host = TapToPayErrorTranslation.hostError(for: mapped)
            XCTAssertEqual((host as? TapToPayError)?.type, .readerDeviceRefused, "\(mapped)")
        }

        /// The same denial during a read reports the refusal, not the read's failure, and ends the reader session.
        func testAVendorDenialInTheErrorListDuringAReadEndsTheReaderSession() {
            let mapped = FiservCardReader.mapError(Self.vendorDeniedInErrorList) { .nfcFailed(reason: $0) }

            let host = TapToPayErrorTranslation.hostError(for: mapped)
            XCTAssertEqual((host as? TapToPayError)?.type, .readerDeviceRefused, "\(mapped)")
            XCTAssertTrue(readerFailureInvalidatesSession(mapped))
        }

        /// A code in the `error` list that is not a denial reports the reader's own case.
        func testAVendorFailureInTheErrorListReportsTheReadersOwnCase() {
            let mapped = FiservCardReader.mapError(Self.vendorFailedInErrorList) { .readerSetupFailed(reason: $0) }

            let host = TapToPayErrorTranslation.hostError(for: mapped)
            XCTAssertEqual((host as? TapToPayError)?.type, .readerUnavailable, "\(mapped)")
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

        /// Built the way `FiservTTPCardReader.charges` rebuilds a refused read: its own title, the refusal's
        /// bridged description, and the refusal itself.
        private static func chargeFailure(behind refusal: Error) -> FiservTTPCardReaderError {
            FiservTTPCardReaderError(title: "Charges", localizedDescription: refusal.localizedDescription, underlying: refusal)
        }

        private static func rebuiltRead(_ error: PaymentCardReaderSession.ReadError) -> FiservTTPCardReaderError {
            FiservTTPCardReaderError(
                title: error.errorName,
                localizedDescription: error.errorDescription,
                underlying: error
            )
        }

        /// The vendor's record of refusing the handset, the shape its failure reason carries.
        private static let vendorDenied = FiservTTPCardReaderError(
            title: "Setup failed",
            localizedDescription: "the vendor refused the device",
            failureReason: #"{"responseCode":"677","responseText":"Declined"}"#
        )

        /// A vendor failure that is not a denial of the handset.
        private static let vendorFailed = FiservTTPCardReaderError(
            title: "Setup failed",
            localizedDescription: "the reader could not be started",
            failureReason: #"{"responseCode":"999","responseText":"Unreachable"}"#
        )

        /// The vendor's server error envelope refusing the handset.
        private static let vendorDeniedInErrorList = FiservTTPCardReaderError(
            title: "Setup failed",
            localizedDescription: "the vendor refused the device",
            failureReason: #"{"gatewayResponse":{"transactionState":"DECLINED"},"error":[{"type":"GATEWAY","code":"677","message":"Device denied"}]}"#
        )

        /// The vendor's server error envelope with a code that is not a denial of the handset.
        private static let vendorFailedInErrorList = FiservTTPCardReaderError(
            title: "Setup failed",
            localizedDescription: "the reader could not be started",
            failureReason: #"{"gatewayResponse":{"transactionState":"FAILED"},"error":[{"type":"GATEWAY","code":"999","message":"Unreachable"}]}"#
        )
    }

#endif
