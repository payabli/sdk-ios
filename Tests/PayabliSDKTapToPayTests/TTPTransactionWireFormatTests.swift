import XCTest
@testable import PayabliSDKTapToPay

/// Contract tests for the backend `PATCH /MoneyIn/update/{id}` wire format.
/// The backend still expects the top-level key `fiservResponse`; the SDK's
/// Swift field is named `providerResponse` and maps to that wire key via
/// `UpdateSuccessBody.CodingKeys`. These tests fail loudly if someone
/// removes or changes the mapping without a coordinated backend rollout.
final class TTPTransactionWireFormatTests: XCTestCase {

    func test_updateSuccessBody_serializesOpaqueJSONUnderFiservResponseKey() throws {
        let innerJSON = Data(#"{"transactionId":"abc","status":"approved"}"#.utf8)
        let payload = ProviderResponsePayload.opaqueJSON(innerJSON)
        let body = UpdateSuccessBody(providerResponse: payload)

        let wire = try JSONEncoder().encode(body)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: wire) as? [String: Any]
        )

        // The wire key must remain `fiservResponse`, not `providerResponse`.
        XCTAssertNotNil(parsed["fiservResponse"], "wire JSON lost the fiservResponse key")
        XCTAssertNil(parsed["providerResponse"], "Swift field name leaked into wire JSON")

        let inner = try XCTUnwrap(parsed["fiservResponse"] as? [String: Any])
        XCTAssertEqual(inner["transactionId"] as? String, "abc")
        XCTAssertEqual(inner["status"] as? String, "approved")
    }

    func test_updateSuccessBody_serializesPayloadOnlyUnderFiservResponseKey() throws {
        let payloadOnly = PayloadOnlyProviderResponse(
            provider: "test",
            encryptedPayload: "ZW5jcnlwdGVkLWJsb2I=",
            cardNetwork: "Visa",
            providerMetadata: ["traceId": "t-1"]
        )
        let body = UpdateSuccessBody(providerResponse: .payloadOnly(payloadOnly))

        let wire = try JSONEncoder().encode(body)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: wire) as? [String: Any]
        )

        let inner = try XCTUnwrap(parsed["fiservResponse"] as? [String: Any])
        XCTAssertEqual(inner["provider"] as? String, "test")
        XCTAssertEqual(inner["cardNetwork"] as? String, "Visa")
        XCTAssertEqual(inner["encryptedPayload"] as? String, "ZW5jcnlwdGVkLWJsb2I=")
    }

    // MARK: - Initiate request — paymentDetails

    func test_initiatePaymentDetails_includesCurrencyAndPaymentDescription() throws {
        let pd = InitiatePaymentDetails(
            totalAmount: Decimal(string: "25.00")!,
            serviceFee: Decimal(string: "1.50")!,
            currency: "USD",
            paymentDescription: "Coffee"
        )
        let wire = try JSONEncoder().encode(pd)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        XCTAssertEqual(parsed["currency"] as? String, "USD")
        XCTAssertEqual(parsed["paymentDescription"] as? String, "Coffee")
    }

    func test_initiatePaymentDetails_omitsPaymentDescriptionWhenNil() throws {
        let pd = InitiatePaymentDetails(
            totalAmount: 10,
            serviceFee: 0,
            currency: "USD",
            paymentDescription: nil
        )
        let wire = try JSONEncoder().encode(pd)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        XCTAssertNil(parsed["paymentDescription"], "paymentDescription should be omitted when nil")
        XCTAssertEqual(parsed["currency"] as? String, "USD")
    }

    /// When the host doesn't pass a `currency`, the field must be omitted from
    /// the wire payload. The backend then authorizes in the merchant's
    /// configured processor currency (the same one the reader uses from
    /// `/config`), so the backend record and processor transaction can't
    /// disagree on currency for non-USD merchants.
    func test_initiatePaymentDetails_omitsCurrencyWhenNil() throws {
        let pd = InitiatePaymentDetails(
            totalAmount: 10,
            serviceFee: 0,
            currency: nil,
            paymentDescription: nil
        )
        let wire = try JSONEncoder().encode(pd)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        XCTAssertNil(parsed["currency"], "currency should be omitted when nil")
    }

    // MARK: - Initiate request — customerData

    func test_initiateCustomerData_omitsOptionalFieldsWhenNil() throws {
        let cd = InitiateCustomerData(
            firstName: "",
            lastName: "",
            customerNumber: "",
            email: nil,
            phone: nil,
            customerId: nil,
            company: nil,
            billingAddress1: nil, billingAddress2: nil,
            billingCity: nil, billingState: nil,
            billingZip: nil, billingCountry: nil,
            billingPhone: nil, billingEmail: nil,
            shippingAddress1: nil, shippingAddress2: nil,
            shippingCity: nil, shippingState: nil,
            shippingZip: nil, shippingCountry: nil
        )
        let wire = try JSONEncoder().encode(cd)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        XCTAssertEqual(parsed["firstName"] as? String, "")
        XCTAssertEqual(parsed["lastName"] as? String, "")
        XCTAssertEqual(parsed["customerNumber"] as? String, "")
        XCTAssertNil(parsed["email"])
        XCTAssertNil(parsed["phone"])
        XCTAssertNil(parsed["customerId"])
        XCTAssertNil(parsed["company"])
        XCTAssertNil(parsed["billingAddress1"])
        XCTAssertNil(parsed["shippingAddress1"])
    }

    func test_initiateCustomerData_serializesAllNewFields() throws {
        let cd = InitiateCustomerData(
            firstName: "Ana",
            lastName: "Lopez",
            customerNumber: "C-1",
            email: "ana@example.com",
            phone: "+1-555-0100",
            customerId: 12345,
            company: "Acme",
            billingAddress1: "1 Market",
            billingAddress2: "Apt 5",
            billingCity: "SF",
            billingState: "CA",
            billingZip: "94105",
            billingCountry: "US",
            billingPhone: "+1-555-0101",
            billingEmail: "billing@example.com",
            shippingAddress1: "2 Pine",
            shippingAddress2: "Suite 9",
            shippingCity: "Oakland",
            shippingState: "CA",
            shippingZip: "94607",
            shippingCountry: "US"
        )
        let wire = try JSONEncoder().encode(cd)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        XCTAssertEqual(parsed["firstName"] as? String, "Ana")
        XCTAssertEqual(parsed["email"] as? String, "ana@example.com")
        XCTAssertEqual(parsed["phone"] as? String, "+1-555-0100")
        XCTAssertEqual(parsed["customerId"] as? Int, 12345)
        XCTAssertEqual(parsed["company"] as? String, "Acme")
        XCTAssertEqual(parsed["billingAddress1"] as? String, "1 Market")
        XCTAssertEqual(parsed["billingCity"] as? String, "SF")
        XCTAssertEqual(parsed["shippingZip"] as? String, "94607")
    }

    func test_initiateCustomerData_serializesCustomerIdAsNumber() throws {
        let cd = InitiateCustomerData(
            firstName: "", lastName: "", customerNumber: "",
            email: nil, phone: nil,
            customerId: 7,
            company: nil,
            billingAddress1: nil, billingAddress2: nil,
            billingCity: nil, billingState: nil,
            billingZip: nil, billingCountry: nil,
            billingPhone: nil, billingEmail: nil,
            shippingAddress1: nil, shippingAddress2: nil,
            shippingCity: nil, shippingState: nil,
            shippingZip: nil, shippingCountry: nil
        )
        let wire = try JSONEncoder().encode(cd)
        let json = String(data: wire, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"customerId\":7"), "expected customerId as number, got: \(json)")
        XCTAssertFalse(json.contains("\"customerId\":\"7\""), "customerId should not serialize as string")
    }

    // MARK: - Initiate request — invoiceData

    func test_initiateInvoiceData_serializesInvoiceNumber() throws {
        let inv = InitiateInvoiceData(invoiceNumber: "INV-1001")
        let wire = try JSONEncoder().encode(inv)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        XCTAssertEqual(parsed["invoiceNumber"] as? String, "INV-1001")
    }

    // MARK: - Initiate request — outer envelope

    func test_initiateRequest_omitsInvoiceDataWhenNil() throws {
        let req = InitiateRequest(
            entryPoint: "e",
            orderDescription: "",
            paymentDetails: InitiatePaymentDetails(
                totalAmount: 10, serviceFee: 0, currency: "USD", paymentDescription: nil
            ),
            paymentMethod: InitiatePaymentMethod(method: "device", device: "d"),
            customerData: InitiateCustomerData(
                firstName: "", lastName: "", customerNumber: "",
                email: nil, phone: nil, customerId: nil, company: nil,
                billingAddress1: nil, billingAddress2: nil, billingCity: nil,
                billingState: nil, billingZip: nil, billingCountry: nil,
                billingPhone: nil, billingEmail: nil,
                shippingAddress1: nil, shippingAddress2: nil, shippingCity: nil,
                shippingState: nil, shippingZip: nil, shippingCountry: nil
            ),
            invoiceData: nil
        )
        let wire = try JSONEncoder().encode(req)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        XCTAssertNil(parsed["invoiceData"], "invoiceData should be omitted when nil")
        XCTAssertNil(parsed["orderId"], "orderId should not appear in the wire")
    }

    func test_initiateRequest_includesInvoiceDataWhenPresent() throws {
        let req = InitiateRequest(
            entryPoint: "e",
            orderDescription: "Coffee",
            paymentDetails: InitiatePaymentDetails(
                totalAmount: 10, serviceFee: 0, currency: "USD", paymentDescription: nil
            ),
            paymentMethod: InitiatePaymentMethod(method: "device", device: "d"),
            customerData: InitiateCustomerData(
                firstName: "", lastName: "", customerNumber: "",
                email: nil, phone: nil, customerId: nil, company: nil,
                billingAddress1: nil, billingAddress2: nil, billingCity: nil,
                billingState: nil, billingZip: nil, billingCountry: nil,
                billingPhone: nil, billingEmail: nil,
                shippingAddress1: nil, shippingAddress2: nil, shippingCity: nil,
                shippingState: nil, shippingZip: nil, shippingCountry: nil
            ),
            invoiceData: InitiateInvoiceData(invoiceNumber: "INV-1")
        )
        let wire = try JSONEncoder().encode(req)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        let invoice = try XCTUnwrap(parsed["invoiceData"] as? [String: Any])
        XCTAssertEqual(invoice["invoiceNumber"] as? String, "INV-1")
    }
}
