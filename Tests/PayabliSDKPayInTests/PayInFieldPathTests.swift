@testable import PayabliSDKPayIn
import XCTest

/// Each form field is named by where its value sits in the request.
final class PayInFieldPathTests: XCTestCase {
    func testEachFormFieldIsNamedByItsPathInTheRequest() {
        let expected: [PayabliPayInField: String] = [
            .cardholderName: "paymentMethod.cardHolder",
            .cardNumber: "paymentMethod.cardnumber",
            .cardExpiration: "paymentMethod.cardexp",
            .cardCvv: "paymentMethod.cardcvv",
            .cardZip: "paymentMethod.cardzip",
            .accountHolder: "paymentMethod.achHolder",
            .routingNumber: "paymentMethod.achRouting",
            .accountNumber: "paymentMethod.achAccount",
            .accountType: "paymentMethod.achAccountType",
            .accountHolderType: "paymentMethod.achHolderType",
            .secCode: "paymentMethod.achCode",
            .deviceId: "paymentMethod.device",
            .methodDescription: "methodDescription",
            .firstName: "customerData.firstName",
            .lastName: "customerData.lastName",
            .customerNumber: "customerData.customerNumber",
            .billingEmail: "customerData.billingEmail",
            .billingZip: "customerData.billingZip",
            .amount: "paymentDetails.totalAmount",
            .serviceFee: "paymentDetails.serviceFee",
            .surchargeFee: "paymentDetails.surchargeFee"
        ]

        XCTAssertEqual(Set(expected.keys), Set(PayabliPayInField.allCases))
        for (field, path) in expected {
            XCTAssertEqual(PayInFieldPath.form(field), path, "\(field)")
        }
    }
}
