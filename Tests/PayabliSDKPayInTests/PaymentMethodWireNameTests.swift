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
            XCTAssertEqual(try Self.sentMethod(PayInBodyWriter.captureFragment(paymentMethod)), expected, name)
            XCTAssertEqual(paymentMethod.method, expected, name)
        }
    }

    func testStoringABankAccountSendsTheServiceMethodName() throws {
        XCTAssertEqual(try Self.sentMethod(PayInBodyWriter.storeFragment(.bankAccount(Self.bankAccount))), "ach")
        XCTAssertEqual(try Self.sentMethod(PayInBodyWriter.storeFragment(.card(Self.card))), "card")
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
        cardNumber: "4111111111111111",
        expiry: "02/28",
        holderName: "Jane Doe",
        securityCode: "123",
        postalCode: "33139"
    )

    private static let bankAccount = PayabliPayInBankAccountData(
        accountNumber: "1111111111",
        accountType: .checking,
        holderName: "Jane Doe",
        routingNumber: "123456780"
    )

    /// The method name in the bytes the body writer produced for the request.
    private static func sentMethod(_ fragment: PayInMethodFragment) throws -> String? {
        let body = try JSONSerialization.jsonObject(with: Data(fragment.rawCopy())) as? [String: Any]
        return body?["method"] as? String
    }
}
