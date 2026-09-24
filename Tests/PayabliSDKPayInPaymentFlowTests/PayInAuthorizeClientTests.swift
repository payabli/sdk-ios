@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

/// Which payment methods an authorization admits, and what is refused before anything is sent.
///
/// Its own class because the client's main suite is at the length the linter allows.
final class PayInAuthorizeClientTests: XCTestCase {
    func testAStoredCardIsAuthorized() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.authorizedResponse)

        _ = try await authorize(
            .stored(PayabliPayInPaymentFlowStoredMethod(method: .card, storedMethodId: "stored-card-1")),
            on: transport
        )

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/authorize")
        let paymentMethod = try Self.paymentMethod(in: request)
        XCTAssertEqual(paymentMethod["method"] as? String, "card")
        XCTAssertEqual(paymentMethod["storedMethodId"] as? String, "stored-card-1")
        XCTAssertEqual(paymentMethod["initiator"] as? String, "payor")
    }

    func testACloudDeviceIsAuthorized() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.authorizedResponse)

        _ = try await authorize(.cloud(PayabliPayInPaymentFlowCloudMethod(device: "device-1")), on: transport)

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/authorize")
        let paymentMethod = try Self.paymentMethod(in: request)
        XCTAssertEqual(paymentMethod["method"] as? String, "cloud")
        XCTAssertEqual(paymentMethod["device"] as? String, "device-1")
    }

    func testACloudDeviceWithNoDeviceIsRefusedBeforeAnythingIsSent() async throws {
        try await assertRefused(
            .cloud(PayabliPayInPaymentFlowCloudMethod(device: "  ")),
            message: "Cloud device is required."
        )
    }

    func testAStoredBankAccountIsRefusedBeforeAnythingIsSent() async throws {
        try await assertRefused(
            .stored(PayabliPayInPaymentFlowStoredMethod(method: .ach, storedMethodId: "stored-ach-1")),
            message: "This payment method cannot be authorized."
        )
    }

    func testABankAccountACheckAndCashAreRefusedBeforeAnythingIsSent() async throws {
        let methods: [PayabliPayInPaymentFlowPaymentMethod] = [
            .ach(PayabliPayInPaymentFlowACHMethod(data: PayabliPayInPaymentFlowACHData(
                accountNumber: "1111111111111",
                accountType: .checking,
                holderName: "John Doe",
                routingNumber: "123456780"
            ))),
            .check(PayabliPayInPaymentFlowCheckMethod(holderName: "John Doe")),
            .cash
        ]
        for method in methods {
            try await assertRefused(method, message: "This payment method cannot be authorized.")
        }
    }

    // MARK: - Support

    private func authorize(
        _ method: PayabliPayInPaymentFlowPaymentMethod,
        on transport: MockPaymentCaptureTransport
    ) async throws -> PayabliPayInPaymentFlowResult {
        try await PayInPaymentFlowClient(transport: transport).authorize(
            entryPoint: "entry",
            request: PayabliPayInPaymentFlowRequest(
                paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 10),
                paymentMethod: method
            ),
            idempotencyKey: "idem-1"
        )
    }

    private func assertRefused(
        _ method: PayabliPayInPaymentFlowPaymentMethod,
        message expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.authorizedResponse)
        do {
            _ = try await authorize(method, on: transport)
            XCTFail("\(method.method) must be refused", file: file, line: line)
        } catch let PayabliPayInPaymentFlowError.invalidInput(message) {
            XCTAssertEqual(message, expected, file: file, line: line)
        } catch {
            XCTFail("Wrong error: \(error)", file: file, line: line)
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty, "\(method.method) must not reach the service", file: file, line: line)
    }

    private static func paymentMethod(in request: PayabliRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        return try XCTUnwrap(body["paymentMethod"] as? [String: Any])
    }

    private static let authorizedResponse = """
    {
      "code": "A0002",
      "reason": "Authorized",
      "data": {
        "paymentTransId": "3040-auth",
        "method": "card",
        "transStatus": 11,
        "operation": "Auth",
        "responseData": {
          "resultCode": "A0002",
          "resultCodeText": "Authorized"
        }
      },
      "token": null
    }
    """
}
