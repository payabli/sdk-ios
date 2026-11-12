@testable import PayabliSDKPayIn
import XCTest

/// What a crash report or a debugger can render about the instrument: the rendering routes that go
/// through `description` refuse to name the card's and the bank account's digits. `dump()` and
/// `Mirror` render the stored fields, which no protocol redacts.
final class PaymentMethodRedactionTests: XCTestCase {
    private let pan = "4111111111111111"
    private let securityCode = "999"
    private let account = "00003400000"

    private func card() -> PayabliPayInCardData {
        PayabliPayInCardData(
            cardNumber: pan,
            expiryMonth: 12,
            expiryYear: 2030,
            securityCode: securityCode,
            holderName: "A Payer",
            postalCode: "22039"
        )
    }

    private func bankAccount() -> PayabliPayInBankAccountData {
        PayabliPayInBankAccountData(
            accountNumber: account,
            routingNumber: "122105278",
            accountType: .checking,
            holderName: "A Payer"
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

    func testCardDataRendersTheSameRedactedTextOnEveryDescriptionRoute() {
        // description is what an interpolated value renders, debugDescription what String(reflecting:)
        // and a debugger's po render: all of them carry the same absence. dump() and the variables view
        // render the stored fields, which no protocol redacts.
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
        } catch let refusal as PayabliPayInError.InvalidInput {
            XCTAssertEqual("Card number must be 12 to 19 digits.", refusal.reason)
            XCTAssertEqual(refusal.field, "paymentMethod.cardnumber")
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
        } catch let refusal as PayabliPayInError.InvalidInput {
            XCTAssertEqual("CVV is required.", refusal.reason)
            XCTAssertEqual(refusal.field, "paymentMethod.cardcvv")
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
        } catch let refusal as PayabliPayInError.InvalidInput {
            XCTAssertEqual("Account number must be 4 to 17 digits.", refusal.reason)
            XCTAssertEqual(refusal.field, "paymentMethod.achAccount")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}
