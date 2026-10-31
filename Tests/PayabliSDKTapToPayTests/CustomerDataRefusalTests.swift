import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// The names a refused customer's text lists reach the host as the customer property that sets each one.
final class CustomerDataRefusalTests: XCTestCase {
    private static let propertyForKey: [(key: String, property: String)] = [
        ("customernumber", "customerNumber"),
        ("firstname", "firstName"),
        ("lastname", "lastName"),
        ("company", "company"),
        ("phone", "billingPhone"),
        ("email", "billingEmail"),
        ("city", "billingCity"),
        ("state", "billingState"),
        ("zip", "billingZip"),
        ("country", "billingCountry"),
        ("shippingcity", "shippingCity"),
        ("shippingstate", "shippingState"),
        ("shippingzip", "shippingZip"),
        ("shippingcountry", "shippingCountry")
    ]

    func testEveryKnownKeyArrivesAsItsCustomerPropertyInAnyCasing() throws {
        for (key, property) in Self.propertyForKey {
            for casing in [key, key.uppercased(), key.capitalized] {
                let refusal = try XCTUnwrap(Self.refusal(listing: casing), casing)
                XCTAssertEqual(refusal.requiredFields, [property], "\(casing)")
            }
        }
    }

    func testEveryKeyInTheServicesJoinArrivesInOrder() throws {
        let refusal = try XCTUnwrap(Self.refusal(listing: "CustomerNumber,Email,ShippingZip"))

        XCTAssertEqual(refusal.requiredFields, ["customerNumber", "billingEmail", "shippingZip"])
    }

    func testAnUnknownKeyPassesThroughAsThePaypointNamesIt() throws {
        let refusal = try XCTUnwrap(Self.refusal(listing: "Email,LoyaltyId"))

        XCTAssertEqual(refusal.requiredFields, ["billingEmail", "LoyaltyId"])
    }

    /// A `400` `E7020` refusal of `customerData` whose text lists `keys` after the service's prefix.
    ///
    /// - Parameter keys: the text after the prefix.
    /// - Returns: the refusal read from it, or nil when it is not read as one.
    private static func refusal(listing keys: String) throws -> CustomerDataRefusal? {
        let message = "Missing customer identifiers: \(keys)"
        let body: [String: Any] = [
            "title": "Bad Request",
            "status": 400,
            "detail": message,
            "code": "E7020",
            "errors": ["customerData": [["message": message, "suggestion": ""]]]
        ]
        return try CustomerDataRefusal(
            response: PayabliResponse(
                statusCode: 400,
                headers: ["Content-Type": "application/json"],
                body: JSONSerialization.data(withJSONObject: body)
            )
        )
    }
}
