@testable import PayabliSDKPayInPaymentFlow
import XCTest

final class PaymentMethodFieldNamingTests: XCTestCase {
    func testBankAccountFieldsTakeTheBankAccountWords() {
        let bankAccountFields: [PayabliPayInPaymentFlowField] = [
            .accountHolder, .routingNumber, .accountNumber, .accountType, .accountHolderType, .secCode, .deviceId
        ]

        XCTAssertEqual(
            bankAccountFields.map(\.rawValue),
            ["accountHolder", "routingNumber", "accountNumber", "accountType", "accountHolderType", "secCode", "deviceId"]
        )
    }

    func testNoFieldIsSpelledWithTheRailName() {
        let spelledWithTheRail = PayabliPayInPaymentFlowField.allCases.map(\.rawValue).filter { $0.lowercased().hasPrefix("ach") }

        XCTAssertEqual(spelledWithTheRail, [])
    }

    func testAccessibilityIdentifiersTakeTheFinalPrefix() {
        XCTAssertEqual(PayabliPayInPaymentFlowAccessibility.fieldIdentifier(.accountHolder), "payabli.payIn.field.accountHolder")
        XCTAssertEqual(PayabliPayInPaymentFlowAccessibility.expirationDoneIdentifier, "payabli.payIn.control.expirationDone")
        XCTAssertEqual(PayabliPayInPaymentFlowAccessibility.keyboardDoneIdentifier, "payabli.payIn.control.keyboardDone")
    }
}
