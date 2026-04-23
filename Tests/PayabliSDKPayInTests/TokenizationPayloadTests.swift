import XCTest
@testable import PayabliSDKPayIn

final class TokenizationPayloadTests: XCTestCase {

    private func jsonObject(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw NSError(domain: "test", code: 0)
        }
        return dict
    }

    // MARK: - Card payload matches PRD §8

    func testCardRequestSerialization() throws {
        let request = CardTokenizationRequest(
            customerData: CustomerDataBlock(customerId: 123),
            entryPoint: "mobile_app",
            paymentMethod: CardTokenizationPayload(
                cardnumber: "4111111111111111",
                cardexp: "0530",
                cardcvv: "123",
                cardHolder: "John Doe",
                cardzip: "90210"
            )
        )

        let data = try JSONEncoder().encode(request)
        let root = try jsonObject(from: data)

        XCTAssertEqual(root["entryPoint"] as? String, "mobile_app")
        XCTAssertEqual(root["fallbackAuth"] as? Bool, true)

        let customer = root["customerData"] as? [String: Any]
        XCTAssertEqual(customer?["customerId"] as? Int, 123)

        let method = root["paymentMethod"] as? [String: Any]
        XCTAssertEqual(method?["method"] as? String, "card")
        XCTAssertEqual(method?["cardnumber"] as? String, "4111111111111111")
        XCTAssertEqual(method?["cardexp"] as? String, "0530")
        XCTAssertEqual(method?["cardcvv"] as? String, "123")
        XCTAssertEqual(method?["cardHolder"] as? String, "John Doe")
        XCTAssertEqual(method?["cardzip"] as? String, "90210")
    }

    // MARK: - ACH payload matches PRD §8

    func testACHRequestSerialization() throws {
        let request = ACHTokenizationRequest(
            customerData: CustomerDataBlock(customerId: 123),
            entryPoint: "mobile_app",
            paymentMethod: ACHTokenizationPayload(
                achAccount: "123456789",
                achRouting: "021000021",
                achAccountType: .checking,
                achHolder: "John Doe",
                achHolderType: .personal
            )
        )

        let data = try JSONEncoder().encode(request)
        let root = try jsonObject(from: data)
        let method = root["paymentMethod"] as? [String: Any]

        XCTAssertEqual(method?["method"] as? String, "ach")
        XCTAssertEqual(method?["achAccount"] as? String, "123456789")
        XCTAssertEqual(method?["achRouting"] as? String, "021000021")
        XCTAssertEqual(method?["achAccountType"] as? String, "Checking")
        XCTAssertEqual(method?["achHolder"] as? String, "John Doe")
        XCTAssertEqual(method?["achHolderType"] as? String, "personal")
        XCTAssertEqual(method?["achCode"] as? String, "WEB") // FR-2.6
    }
}
