@testable import PayabliSDKPayIn
import XCTest

final class PaymentMethodWireNameTests: XCTestCase {
    func testEachPaymentMethodSendsTheServiceMethodName() throws {
        let cases: [(String, PayabliPayInPaymentMethod, String)] = [
            ("card", .card(.init(data: Self.card)), "card"),
            ("bankAccount", .bankAccount(.init(data: Self.bankAccount)), "ach"),
            ("stored card", .stored(.init(method: .card, storedMethodId: "stored-card")), "card"),
            ("stored bankAccount", .stored(.init(method: .bankAccount, storedMethodId: "stored-bank")), "ach"),
            ("cloudDevice", .cloudDevice(.init(device: "device-1")), "cloud"),
            ("check", .check(.init(holderName: "Jane Doe")), "check"),
            ("cash", .cash, "cash")
        ]

        for (name, paymentMethod, expected) in cases {
            XCTAssertEqual(try Self.sentMethod(paymentMethod), expected, name)
            XCTAssertEqual(paymentMethod.method, expected, name)
        }
    }

    func testStoringABankAccountSendsTheServiceMethodName() throws {
        XCTAssertEqual(try Self.sentMethod(PayabliPayInMethodInput.bankAccount(Self.bankAccount)), "ach")
        XCTAssertEqual(try Self.sentMethod(PayabliPayInMethodInput.card(Self.card)), "card")
    }

    func testMethodEnumsKeepTheServiceWords() {
        XCTAssertEqual(PayabliPayInStoredMethodType.allCases.map(\.rawValue), ["card", "ach"])
        XCTAssertEqual(PayabliPayInMethodType.allCases.map(\.rawValue), ["card", "ach"])
    }

    private static let card = PayabliPayInCardData(
        cardNumber: "4111111111111111",
        expiration: "02/28",
        cardholderName: "Jane Doe",
        cvv: "123",
        billingZip: "33139"
    )

    private static let bankAccount = PayabliPayInBankAccountData(
        accountNumber: "1111111111",
        accountType: .checking,
        holderName: "Jane Doe",
        routingNumber: "123456780"
    )

    private static func sentMethod(_ value: some Encodable) throws -> String? {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
        return body?["method"] as? String
    }
}
