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

    func testMethodEnumsReadTheServiceWordsBack() {
        XCTAssertEqual(PayabliPayInMethodType(rawValue: "card"), .card)
        XCTAssertEqual(PayabliPayInMethodType(rawValue: "ach"), .bankAccount)
        XCTAssertNil(PayabliPayInMethodType(rawValue: "bankAccount"))
        XCTAssertNil(PayabliPayInMethodType(rawValue: "cloud"))

        XCTAssertEqual(PayabliPayInStoredMethodType(rawValue: "card"), .card)
        XCTAssertEqual(PayabliPayInStoredMethodType(rawValue: "ach"), .bankAccount)
        XCTAssertNil(PayabliPayInStoredMethodType(rawValue: "bankAccount"))
        XCTAssertNil(PayabliPayInStoredMethodType(rawValue: "wallet"))
    }

    func testStoredMethodTypeCodesAsTheServiceWord() throws {
        let encoded = try JSONEncoder().encode(PayabliPayInStoredMethodType.allCases)
        XCTAssertEqual(String(bytes: encoded, encoding: .utf8), #"["card","ach"]"#)
        XCTAssertEqual(
            try JSONDecoder().decode([PayabliPayInStoredMethodType].self, from: encoded),
            PayabliPayInStoredMethodType.allCases
        )
        XCTAssertThrowsError(try JSONDecoder().decode(PayabliPayInStoredMethodType.self, from: Data(#""wallet""#.utf8)))
    }

    private static let card = PayabliPayInCardData(
        cardNumber: SensitiveDigits.ofString("4111111111111111"),
        expiry: "02/28",
        holderName: "Jane Doe",
        securityCode: SensitiveDigits.ofString("123"),
        postalCode: "33139"
    )

    private static let bankAccount = PayabliPayInBankAccountData(
        accountNumber: SensitiveDigits.ofString("1111111111"),
        accountType: .checking,
        holderName: "Jane Doe",
        routingNumber: "123456780"
    )

    private static func sentMethod(_ value: some Encodable) throws -> String? {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
        return body?["method"] as? String
    }
}
