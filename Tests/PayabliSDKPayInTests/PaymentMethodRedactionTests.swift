@testable import PayabliSDKPayIn
import XCTest

/// What a crash report or a debugger can render about the instrument: the two data types carry the
/// card's and the bank account's digits, so every rendering route has to refuse to name them.
final class PaymentMethodRedactionTests: XCTestCase {
    private let pan = "4111111111111111"
    private let securityCode = "999"
    private let account = "00003400000"

    private func card() -> PayabliPayInCardData {
        PayabliPayInCardData(
            cardNumber: SensitiveDigits.ofString(pan),
            expiry: "12/30",
            holderName: "A Payer",
            securityCode: SensitiveDigits.ofString(securityCode),
            postalCode: "22039"
        )
    }

    private func bankAccount() -> PayabliPayInBankAccountData {
        PayabliPayInBankAccountData(
            accountNumber: SensitiveDigits.ofString(account),
            accountType: .checking,
            holderName: "A Payer",
            routingNumber: "122105278"
        )
    }

    func testCardDataCarriesNothingAboutTheCardExpiryIncluded() {
        let rendered = card().description

        // The expiry is on the same never-logged list as the number and the security code, so it is absent
        // too: an interpolated value in a crash report would otherwise carry it.
        for item in [pan, securityCode, "A Payer", "22039", "2030", "12"] {
            XCTAssertFalse(rendered.contains(item), item)
        }
        XCTAssertEqual("PayabliPayInCardData", rendered)
    }

    func testCardDataRendersTheSameRedactedTextOnEveryRoute() {
        // description is what an interpolated value renders, debugDescription what a debugger renders,
        // and String(reflecting:) what a formatter renders: all three carry the same absence.
        XCTAssertEqual(card().description, card().debugDescription)
        XCTAssertEqual("PayabliPayInCardData", String(reflecting: card()))
    }

    func testBankDataCarriesNoAccountNumber() {
        let rendered = bankAccount().description

        [account, "A Payer"].forEach { XCTAssertFalse(rendered.contains($0), $0) }
        XCTAssertEqual("PayabliPayInBankAccountData(accountType=Checking)", rendered)
        XCTAssertEqual(rendered, bankAccount().debugDescription)
        XCTAssertEqual(rendered, String(reflecting: bankAccount()))
    }

    func testAWipedCardNumberFailsValidationAsAMissingField() {
        // A closed value has to fail as a missing field, not blow up an encoder: this is the failure a
        // caller that wipes its buffer too early produces.
        let data = card()
        data.cardNumber.close()

        do {
            try data.validate(.default)
            XCTFail("Expected a validation failure")
        } catch let PayabliPayInTokenStorageError.invalidInput(message) {
            XCTAssertEqual("Card number must be 12 to 19 digits.", message)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testAWipedSecurityCodeFailsValidationAsAMissingField() {
        let data = card()
        data.securityCode.close()

        do {
            try data.validate(.default)
            XCTFail("Expected a validation failure")
        } catch let PayabliPayInTokenStorageError.invalidInput(message) {
            XCTAssertEqual("CVV is required.", message)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testAWipedAccountNumberFailsValidationAsAMissingField() {
        let data = bankAccount()
        data.accountNumber.close()

        do {
            try data.validate(.default)
            XCTFail("Expected a validation failure")
        } catch let PayabliPayInTokenStorageError.invalidInput(message) {
            XCTAssertEqual("Account number must be 4 to 17 digits.", message)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}
