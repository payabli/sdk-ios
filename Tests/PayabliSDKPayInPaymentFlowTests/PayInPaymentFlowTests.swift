@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

@MainActor
final class PayInPaymentFlowTests: XCTestCase {
    func testStoresCardPaymentMethodThroughUnifiedComponent() async throws {
        let transport = MockPayInPaymentFlowTransport(responseBody: Self.storedMethodResponse)
        let component = PayabliPayInPaymentFlow(
            entryPoint: "entry",
            environment: .sandbox,
            accessTokenProvider: { "access-token" },
            transport: transport,
            operation: .storePaymentMethod
        )

        let result = try await component.addCard(PayabliPayInPaymentFlowCardData(
            cardNumber: "4111 1111 1111 1111",
            expiration: "02/25",
            cardholderName: "John Doe",
            cvv: "123",
            billingZip: "12345"
        ))

        XCTAssertEqual(result.storedMethodId, "stored-123")
        XCTAssertEqual(component.lastResult?.kind, .storedPaymentMethod)

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.path, "/api/TokenStorage/add")
        XCTAssertNil(request.headers["Authorization"], "the client contributes no credential")
        XCTAssertNil(request.headers["requestToken"])
    }

    func testCaptureUsesMoneyInClientAndFixedCurrencyFormatting() async throws {
        let transport = MockPayInPaymentFlowTransport(responseBody: Self.approvedResponse)
        let component = PayabliPayInPaymentFlow(
            entryPoint: "entry",
            environment: .sandbox,
            accessTokenProvider: { "access-token" },
            transport: transport,
            operation: .capture
        )

        let result = try await component.capture(PayabliPayInPaymentFlowRequest(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
                totalAmount: 1,
                serviceFee: 0.1 + 0.000_000_000_001
            ),
            paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(
                data: PayabliPayInPaymentFlowCardData(
                    cardNumber: "4111 1111 1111 1111",
                    expiration: "02/25",
                    cardholderName: "John Doe",
                    cvv: "123",
                    billingZip: "12345"
                )
            ))
        ))

        XCTAssertEqual(result.kind, .transaction)
        XCTAssertEqual(result.code, "A0000")

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/getpaid")
        let body = try XCTUnwrap(request.body)
        let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(bodyText.contains(#""totalAmount":1.00"#), bodyText)
        XCTAssertTrue(bodyText.contains(#""serviceFee":0.10"#), bodyText)
    }

    private static let storedMethodResponse = """
    {
      "responseText": "Success",
      "isSuccess": true,
      "responseData": {
        "referenceId": "stored-123",
        "resultCode": 1,
        "resultText": "Approved",
        "customerId": 4440,
        "methodReferenceId": "stored-123"
      }
    }
    """

    private static let approvedResponse = """
    {
      "code": "A0000",
      "reason": "Approved",
      "explanation": "Approved by card network or card issuer.",
      "action": "No action required.",
      "data": {
        "paymentTransId": "3040-transaction",
        "method": "card",
        "transStatus": 1,
        "operation": "Sale"
      },
      "token": null
    }
    """
}

private actor MockPayInPaymentFlowTransport: PayabliTransport {
    private(set) var requests: [PayabliRequest] = []
    private let responseBody: String

    init(responseBody: String) {
        self.responseBody = responseBody
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        requests.append(request)
        return PayabliResponse(
            statusCode: 201,
            headers: [:],
            body: Data(responseBody.utf8)
        )
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        requests.append(request)
        return try JSONDecoder().decode(PayabliV2Envelope<T>.self, from: Data(responseBody.utf8))
    }
}

private func firstRequest(from transport: MockPayInPaymentFlowTransport) async throws -> PayabliRequest {
    let requests = await transport.requests
    return try XCTUnwrap(requests.first)
}
