@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

/// A method stored through the form is charged from the result alone.
@MainActor
final class StoredMethodRoundTripTests: XCTestCase {
    func testACardStoredThroughTheFormIsChargedAsACard() async throws {
        let transport = RoutedTransport()
        let component = PayabliPayInPaymentFlow(entryPoint: "entry", environment: .sandbox, transport: transport)
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: component,
            configuration: PayabliPayInPaymentFlowFormConfiguration(allowedMethods: [.card])
        )
        viewModel.cardNumber = "4111 1111 1111 1111"
        viewModel.cardExpiration = "02/25"
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardCvv = "321"
        viewModel.cardZip = "33139"

        let submitted = try await viewModel.submit()
        let stored = try XCTUnwrap(submitted.storedPaymentMethod)
        let paymentMethod = try await chargedPaymentMethod(stored, on: component, transport: transport)

        XCTAssertEqual(paymentMethod["method"] as? String, "card")
        XCTAssertEqual(paymentMethod["storedMethodId"] as? String, "stored-123")
    }

    func testABankAccountStoredThroughTheFormIsChargedAsABankAccount() async throws {
        let transport = RoutedTransport()
        let component = PayabliPayInPaymentFlow(entryPoint: "entry", environment: .sandbox, transport: transport)
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: component,
            configuration: PayabliPayInPaymentFlowFormConfiguration(allowedMethods: [.bankAccount], defaultMethod: .bankAccount)
        )
        viewModel.accountHolder = "Jane Doe"
        viewModel.routingNumber = "123456780"
        viewModel.accountNumber = "1111111111111"

        let submitted = try await viewModel.submit()
        let stored = try XCTUnwrap(submitted.storedPaymentMethod)
        let paymentMethod = try await chargedPaymentMethod(stored, on: component, transport: transport)

        XCTAssertEqual(paymentMethod["method"] as? String, "ach")
        XCTAssertEqual(paymentMethod["storedMethodId"] as? String, "stored-123")
    }

    private func chargedPaymentMethod(
        _ stored: PayabliPayInPaymentFlowStoredPaymentMethod,
        on component: PayabliPayInPaymentFlow,
        transport: RoutedTransport
    ) async throws -> [String: Any] {
        _ = try await component.capture(PayabliPayInPaymentFlowRequest(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 1),
            paymentMethod: .stored(PayabliPayInPaymentMethod.Stored(
                method: stored.method,
                storedMethodId: try XCTUnwrap(stored.storedMethodId)
            ))
        ))

        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.path), ["/api/TokenStorage/add", "/api/v2/MoneyIn/getpaid"])
        let body = try XCTUnwrap(requests.last?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try XCTUnwrap(json["paymentMethod"] as? [String: Any])
    }
}

/// Answers the store route with a stored method and any other route with an approved charge.
private actor RoutedTransport: PayabliTransport {
    private(set) var requests: [PayabliRequest] = []

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        requests.append(request)
        let body = request.path == "/api/TokenStorage/add" ? Self.stored : Self.approved
        return PayabliResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        requests.append(request)
        return try JSONDecoder().decode(PayabliV2Envelope<T>.self, from: Data(Self.approved.utf8))
    }

    private static let stored = """
    {
      "responseText": "Success",
      "isSuccess": true,
      "responseData": {
        "referenceId": "stored-123",
        "resultCode": 1,
        "resultText": "Approved",
        "methodReferenceId": "stored-123"
      }
    }
    """

    private static let approved = """
    {
      "code": "A0000",
      "reason": "Approved",
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
