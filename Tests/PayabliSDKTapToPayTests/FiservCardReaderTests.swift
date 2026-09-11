@testable import PayabliSDKTapToPay
import XCTest

final class FiservCardReaderTests: XCTestCase {
    func testProviderId() {
        XCTAssertEqual(FiservCardReader.providerId, "fiserv")
    }

    /// Eligibility is platform/hardware-only (PRD FR-11J.2) and is called before
    /// `/config` delivers credentials — so a fresh reader on a supported device
    /// must report `success`.
    func testEligibilityIsPlatformOnly() async {
        let reader = FiservCardReader()
        let result = await reader.checkEligibility()
        #if os(iOS)
            if #available(iOS 16.7, *) {
                // On a real iPhone `success`; on an incompatible device
                // `readerSetupFailed`. Both are acceptable, so the assertion is
                // only that the error, if any, is not about missing credentials.
                if case let .failure(err) = result, case let .readerSetupFailed(reason) = err {
                    XCTAssertFalse(
                        reason.lowercased().contains("credentials"),
                        "eligibility should not require credentials"
                    )
                }
            } else {
                if case .success = result {
                    XCTFail("iOS < 16.7 must fail eligibility")
                }
            }
        #else
            if case .success = result {
                XCTFail("non-iOS must fail eligibility")
            }
        #endif
    }

    func testPrepareReaderRequiresCredentials() async {
        let reader = FiservCardReader()
        do {
            try await reader.prepareReader()
            XCTFail("expected readerSetupFailed")
        } catch let PayabliTTPError.readerSetupFailed(reason) {
            XCTAssertTrue(
                reason.lowercased().contains("credentials") || reason.lowercased().contains("ios-only"),
                "unexpected reason: \(reason)"
            )
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testConfigureWithFullCredentialsSucceeds() throws {
        let reader = FiservCardReader()
        try reader.configure(credentials: [
            "secretKey": "s",
            "apiKey": "a",
            "environment": "sandbox",
            "currencyCode": "USD",
            "merchantId": "m",
            "appleTtpMerchantId": "atm",
            "merchantName": "Test",
            "merchantCategoryCode": "1000",
            "terminalId": "t",
            "terminalProfileId": "tp"
        ])
    }

    func testConfigureMissingRequiredKeyThrows() {
        let reader = FiservCardReader()
        do {
            // Missing `merchantId` and `terminalId`.
            try reader.configure(credentials: [
                "secretKey": "s",
                "apiKey": "a"
            ])
            XCTFail("expected readerSetupFailed")
        } catch let PayabliTTPError.readerSetupFailed(reason) {
            XCTAssertTrue(reason.contains("merchantId"))
            XCTAssertTrue(reason.contains("terminalId"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testConfigureEmptyRequiredFieldThrows() {
        let reader = FiservCardReader()
        do {
            try reader.configure(credentials: [
                "secretKey": "s",
                "apiKey": "a",
                "merchantId": "",
                "terminalId": "t"
            ])
            XCTFail("expected readerSetupFailed")
        } catch let PayabliTTPError.readerSetupFailed(reason) {
            XCTAssertTrue(reason.contains("merchantId"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testCleanUpClearsCredentials() async {
        let reader = FiservCardReader()
        reader.setCredentials(
            FiservCardReader.Credentials(
                secretKey: "s",
                apiKey: "a",
                environment: "sandbox",
                currencyCode: "USD",
                merchantId: "m",
                appleTtpMerchantId: "atm",
                merchantName: "Test",
                merchantCategoryCode: "1000",
                terminalId: "t",
                terminalProfileId: "tp"
            )
        )
        await reader.cleanUp()
        // After cleanUp, prepareReader should fail because credentials are gone.
        do {
            try await reader.prepareReader()
            XCTFail("expected failure after cleanUp")
        } catch PayabliTTPError.readerSetupFailed {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// With no reader there is nothing to ask, and the adapter says so rather than
    /// answering `false`. A caller cannot otherwise tell a merchant who has not
    /// accepted from a reader that was never prepared.
    ///
    /// The answering branches are covered below, through `setLinkStateSource`,
    /// and the setup path through `setReaderFactory`. What no test here reaches
    /// is a real reader: `isAccountLinked()` needs `PaymentCardReader`, which a
    /// simulator has none of, so what a live platform answers for an unaccepted
    /// merchant is proved on the manual device tier and nowhere else.
    func testTermsCannotBeAnsweredWithoutAPreparedReader() async {
        let reader = FiservCardReader()
        do {
            _ = try await reader.areTermsAccepted()
            XCTFail("expected failure with no prepared reader")
        } catch PayabliTTPError.readerSetupFailed {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testTermsAreReportedAcceptedWhenTheReaderSaysSo() async throws {
        let reader = FiservCardReader()
        reader.setLinkStateSource(StubLinkState(.success(true)))

        let accepted = try await reader.areTermsAccepted()

        XCTAssertTrue(accepted)
    }

    func testTermsAreReportedUnacceptedWhenTheReaderSaysSo() async throws {
        let reader = FiservCardReader()
        reader.setLinkStateSource(StubLinkState(.success(false)))

        let accepted = try await reader.areTermsAccepted()

        XCTAssertFalse(accepted)
    }

    func testPresentingReachesTheReader() async throws {
        let reader = FiservCardReader()
        let source = StubLinkState(.success(false))
        reader.setLinkStateSource(source)

        try await reader.presentTerms()

        XCTAssertEqual(source.linkAccountCalls, 1)
    }

    /// The sheet needs the session token the reader obtained, so there is nothing to present from
    /// before one is prepared. That is a different answer from the merchant declining, and a caller
    /// showing a terms screen has to tell them apart.
    func testPresentingWithoutAReaderSaysSoRatherThanFailingQuietly() async {
        let reader = FiservCardReader()

        do {
            try await reader.presentTerms()
            XCTFail("expected the missing reader to surface")
        } catch PayabliTTPError.readerSetupFailed {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// A platform failure while presenting keeps its shape rather than reading as a dismissal.
    func testAReaderThatRaisesWhilePresentingIsMapped() async {
        let reader = FiservCardReader()
        struct PlatformFailure: Error {}
        reader.setLinkStateSource(StubLinkState(.success(false), linkResult: .failure(PlatformFailure())))

        do {
            try await reader.presentTerms()
            XCTFail("expected the reader's failure to surface")
        } catch PayabliTTPError.readerSetupFailed {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// Dismissing the terms sheet is a failed presentation, not a failed card read. The charge mapper
    /// used to hard-code cancel as `.nfcFailed`, so this call borrowed that label with no NFC underway.
    func testDismissingTheTermsSheetIsASetupFailureNotAnNfcOne() async {
        let reader = FiservCardReader()
        let cancel = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        reader.setLinkStateSource(StubLinkState(.success(false), linkResult: .failure(cancel)))

        do {
            try await reader.presentTerms()
            XCTFail("expected dismissal to surface")
        } catch let error as PayabliTTPError {
            guard case let .readerSetupFailed(reason) = error else {
                return XCTFail("expected readerSetupFailed, got \(error)")
            }
            XCTAssertTrue(
                reason.hasPrefix(FiservCardReader.cancellationReasonPrefix),
                "cancel keeps the prefix a host already matches: \(reason)"
            )
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// A reader that raises is not a merchant who declined, so the failure keeps
    /// its own shape instead of collapsing into `false`.
    func testAReaderThatRaisesIsMappedRatherThanReportedAsUnaccepted() async {
        let reader = FiservCardReader()
        struct PlatformFailure: Error {}
        reader.setLinkStateSource(StubLinkState(.failure(PlatformFailure())))

        do {
            _ = try await reader.areTermsAccepted()
            XCTFail("expected the reader's failure to surface")
        } catch PayabliTTPError.readerSetupFailed {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Classifying a setup failure

    /// Drives `prepareReader()` against a stub reader, so nothing here reaches `PaymentCardReader`.
    private func preparedReader(_ stub: StubReaderSetup) -> FiservCardReader {
        let reader = FiservCardReader()
        reader.setCredentials(.init(
            secretKey: "s", apiKey: "a", environment: "sandbox", currencyCode: "USD",
            merchantId: "m", appleTtpMerchantId: "t", merchantName: "n",
            merchantCategoryCode: "5999", terminalId: "t1", terminalProfileId: "p1"
        ))
        reader.setReaderFactory { _ in stub }
        return reader
    }

    /// The terms case: the platform refuses to open a session and the merchant is not linked.
    ///
    /// The reader has to survive it. It holds the session token presenting the sheet needs, so
    /// clearing it would leave the host with a failure it cannot act on, which is the whole reason
    /// this failure is classified apart from the others.
    func testAnUnlinkedMerchantRefusedASessionIsTermsAndKeepsTheReader() async throws {
        let stub = StubReaderSetup(
            linked: false,
            linkTakes: false,
            sessionResult: .failure(PayabliTTPError.readerSetupFailed(reason: "refused"))
        )
        let reader = preparedReader(stub)

        do {
            try await reader.prepareReader()
            XCTFail("expected the refusal to surface")
        } catch PayabliTTPError.termsNotAccepted {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }

        // Still there to present from and to ask again, which is what "kept" has to mean: a
        // torn-down reader answers `readerSetupFailed` rather than an acceptance state.
        let accepted = try await reader.areTermsAccepted()
        XCTAssertFalse(accepted, "the merchant has not accepted, and the reader must still say so")
    }

    /// A merchant who is linked, whose session still fails, is an ordinary failure.
    ///
    /// This is the half the narrowed catch gets right: the follow-up question answers `true`, so
    /// the original error goes on unchanged rather than being read as a refusal over terms.
    func testALinkedMerchantWhoseSessionFailsIsAnOrdinaryFailure() async {
        let stub = StubReaderSetup(
            linked: true,
            sessionResult: .failure(PayabliTTPError.readerSetupFailed(reason: "connection lost"))
        )
        let reader = preparedReader(stub)

        do {
            try await reader.prepareReader()
            XCTFail("expected the failure to surface")
        } catch PayabliTTPError.termsNotAccepted {
            XCTFail("a linked merchant's failure is not a terms refusal")
        } catch PayabliTTPError.readerSetupFailed {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// Failing before the session is opened is never the terms case.
    ///
    /// The token request is an ordinary network call, and a merchant who has not accepted is still
    /// unlinked while it fails, so without the scoping this would read as unaccepted terms.
    func testATokenFailureIsNeverTermsEvenForAnUnlinkedMerchant() async {
        let stub = StubReaderSetup(
            linked: false,
            tokenResult: .failure(PayabliTTPError.readerSetupFailed(reason: "no network"))
        )
        let reader = preparedReader(stub)

        do {
            try await reader.prepareReader()
            XCTFail("expected the token failure to surface")
        } catch PayabliTTPError.termsNotAccepted {
            XCTFail("a token failure is not a terms refusal")
        } catch PayabliTTPError.readerSetupFailed {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }

        XCTAssertEqual(stub.initializeSessionCalls, 0, "the session must not be opened after this")
    }

    /// **What this classification cannot do, recorded rather than implied.**
    ///
    /// `initializeSession()` is itself compound: it re-requests an expiring token and then prepares
    /// the reader. So an operational failure inside it, for a merchant who has also not accepted,
    /// is reported as unaccepted terms. The platform's typed refusal does not survive the vendored
    /// wrapper, which rewraps every case as its own error carrying prose, so the reader is asked
    /// instead and answers the same either way.
    ///
    /// Bounded rather than harmless: the merchant genuinely has not accepted, so presenting the
    /// terms is still the host's next step, and the operational failure surfaces again on the
    /// initialize that follows. This case exists so the limit is on the record and fails here if it
    /// ever changes.
    func testAnUnlinkedMerchantsOperationalFailureIsReportedAsTerms() async {
        let stub = StubReaderSetup(
            linked: false,
            linkTakes: false,
            sessionResult: .failure(PayabliTTPError.readerSetupFailed(reason: "connection lost"))
        )
        let reader = preparedReader(stub)

        do {
            try await reader.prepareReader()
            XCTFail("expected a failure")
        } catch PayabliTTPError.termsNotAccepted {
            // The documented limit, not the ideal answer.
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// The implicit link still runs on this branch, which is what keeps the terms state the narrow
    /// case until the second pull request removes it.
    func testAnUnlinkedMerchantIsStillLinkedImplicitly() async throws {
        let stub = StubReaderSetup(linked: false)
        let reader = preparedReader(stub)

        try await reader.prepareReader()

        XCTAssertEqual(stub.linkAccountCalls, 1)
        XCTAssertEqual(stub.initializeSessionCalls, 1)
    }
}

/// A reader for the setup path, so `prepareReader()` can be driven without hardware.
///
/// `linked` is the merchant's acceptance, and `isAccountLinked()` answers from it throughout, the
/// way a real reader does. That is what makes the classification measurable: the question is asked
/// again after a failure, and a stub answering from a fixed script could not tell the cases apart.
private final class StubReaderSetup: ReaderSetup {
    private let lock = NSLock()
    private var linked: Bool
    private let linkTakes: Bool
    private let tokenResult: Result<Void, Error>
    private let sessionResult: Result<Void, Error>

    private(set) var initializeSessionCalls = 0
    private(set) var linkAccountCalls = 0

    /// `linkTakes: false` is the lapse the vendor documents: the request returns and the merchant
    /// is still not linked. On this branch that is the only route to the terms state, because the
    /// implicit call otherwise links them before the session is opened.
    init(
        linked: Bool,
        linkTakes: Bool = true,
        tokenResult: Result<Void, Error> = .success(()),
        sessionResult: Result<Void, Error> = .success(())
    ) {
        self.linked = linked
        self.linkTakes = linkTakes
        self.tokenResult = tokenResult
        self.sessionResult = sessionResult
    }

    func requestSessionToken() async throws {
        try tokenResult.get()
    }

    func isAccountLinked() async throws -> Bool {
        lock.withLock { linked }
    }

    func linkAccount() async throws {
        lock.withLock {
            linkAccountCalls += 1
            if linkTakes {
                linked = true
            }
        }
    }

    func initializeSession() async throws {
        lock.withLock { initializeSessionCalls += 1 }
        try sessionResult.get()
    }
}

/// Answers the linked state in place of a reader, which cannot be built without
/// hardware, and stands in for the sheet the reader would present.
private final class StubLinkState: AccountLinking {
    private let lock = NSLock()
    private var result: Result<Bool, Error>
    private let linkResult: Result<Void, Error>
    private let acceptsOnPresent: Bool

    private(set) var linkAccountCalls = 0

    /// `acceptsOnPresent` makes the stub answer `true` after the sheet has been presented, which is
    /// what a real reader does once the merchant accepts. Left off, presenting changes no answer.
    init(
        _ result: Result<Bool, Error>,
        linkResult: Result<Void, Error> = .success(()),
        acceptsOnPresent: Bool = false
    ) {
        self.result = result
        self.linkResult = linkResult
        self.acceptsOnPresent = acceptsOnPresent
    }

    func isAccountLinked() async throws -> Bool {
        try lock.withLock { result }.get()
    }

    func linkAccount() async throws {
        lock.withLock { linkAccountCalls += 1 }
        if case let .failure(err) = linkResult {
            throw err
        }
        if acceptsOnPresent {
            lock.withLock { result = .success(true) }
        }
    }
}
