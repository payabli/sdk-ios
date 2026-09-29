@testable import PayabliSDKPayIn
import XCTest

final class PaymentMethodFieldNamingTests: XCTestCase {
    func testBankAccountFieldsTakeTheBankAccountWords() {
        let bankAccountFields: [PayabliPayInField] = [
            .accountHolder, .routingNumber, .accountNumber, .accountType, .accountHolderType, .secCode, .deviceId
        ]

        XCTAssertEqual(
            bankAccountFields.map(\.rawValue),
            ["accountHolder", "routingNumber", "accountNumber", "accountType", "accountHolderType", "secCode", "deviceId"]
        )
    }

    func testNoFieldIsSpelledWithTheRailName() {
        let spelledWithTheRail = PayabliPayInField.allCases.map(\.rawValue).filter { $0.lowercased().hasPrefix("ach") }

        XCTAssertEqual(spelledWithTheRail, [])
    }

    func testAccessibilityIdentifiersTakeTheFinalPrefix() {
        XCTAssertEqual(PayabliPayInAccessibility.fieldIdentifier(.accountHolder), "payabli.payIn.field.accountHolder")
        XCTAssertEqual(PayabliPayInAccessibility.expirationDoneIdentifier, "payabli.payIn.control.expirationDone")
        XCTAssertEqual(PayabliPayInAccessibility.keyboardDoneIdentifier, "payabli.payIn.control.keyboardDone")
    }
}
