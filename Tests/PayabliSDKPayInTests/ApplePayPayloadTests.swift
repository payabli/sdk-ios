import XCTest
@testable import PayabliSDKPayIn

final class ApplePayPayloadTests: XCTestCase {

    func testApplePayTokenizationPayloadMatchesPRD() throws {
        let request = ApplePayTokenizationRequest(
            customerData: CustomerDataBlock(customerId: 123),
            entryPoint: "mobile_app",
            paymentMethod: ApplePayTokenizationPayload(
                applePayToken: "base64-token",
                applePayNetwork: "Visa",
                applePayDisplayName: "Visa 1234"
            )
        )
        let data = try JSONEncoder().encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let method = dict?["paymentMethod"] as? [String: Any]
        XCTAssertEqual(method?["method"] as? String, "applepay")
        XCTAssertEqual(method?["applePayToken"] as? String, "base64-token")
        XCTAssertEqual(method?["applePayNetwork"] as? String, "Visa")
        XCTAssertEqual(method?["applePayDisplayName"] as? String, "Visa 1234")
    }

    func testGetpaidApplePayMethodSetsFields() throws {
        let token = ApplePayToken(
            paymentData: Data("abc".utf8),
            network: "Mastercard",
            displayName: "MC 1234"
        )
        let method = GetpaidApplePayMethod(
            token: token,
            saveIfSuccess: true,
            initiator: .payor
        )
        let data = try JSONEncoder().encode(method)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["method"] as? String, "applepay")
        XCTAssertEqual(dict?["applePayToken"] as? String, Data("abc".utf8).base64EncodedString())
        XCTAssertEqual(dict?["applePayNetwork"] as? String, "Mastercard")
        XCTAssertEqual(dict?["initiator"] as? String, "payor")
        XCTAssertEqual(dict?["saveIfSuccess"] as? Bool, true)
    }
}
