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
    /// The answering branches are covered below, through `setLinkStateSource`.
    /// What no test here reaches is a real reader: `prepareReader()` cannot get
    /// past `requestSessionToken()` without hardware, so whether an unaccepted
    /// merchant leaves the reader able to answer at all is proved on the manual
    /// device tier and nowhere else.
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
