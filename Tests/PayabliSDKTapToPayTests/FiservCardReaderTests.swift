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
    /// This is the only half of `areTermsAccepted()` a unit test reaches. The
    /// answering path needs a prepared reader, and `prepareReader()` cannot get
    /// past `requestSessionToken()` without reader hardware, so whether an
    /// unaccepted merchant leaves the reader able to answer is proved on the
    /// manual device tier and nowhere else.
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
}
