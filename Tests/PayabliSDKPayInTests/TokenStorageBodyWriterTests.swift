@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// The token-storage route's body as bytes: the method's members spliced in as the body's last one,
/// and the refusal that keeps a non-ASCII digit off the transport.
final class TokenStorageBodyWriterTests: XCTestCase {
    /// The card's own bytes: one object, the payment method as its last member, and the card number
    /// and security code as digits with the entry's separators dropped.
    func testTheCardMethodIsWrittenAsBytesAsTheBodyLastMember() async throws {
        let transport = MockTransport(responseBody: """
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
        """)
        let client = PayInPaymentFlowTokenStorageClient(
            transport: transport
        )

        _ = try await client.addMethod(
            entryPoint: "f743aed24a",
            paymentMethod: .card(PayabliPayInCardData(
                cardNumber: SensitiveDigits.ofString("4111 1111 1111 1111"),
                expiry: "02/25",
                holderName: "John Doe",
                securityCode: SensitiveDigits.ofString("123"),
                postalCode: "12345"
            )),
            options: PayabliPayInOptions(
                createAnonymous: true,
                forceCustomerCreation: false,
                temporary: true,
                customerData: PayabliPayInCustomerData(customerId: 4440),
                fallbackAuth: true,
                fallbackAuthAmount: 100,
                methodDescription: "Primary Visa card",
                source: "ios-sdk",
                subdomain: "checkout"
            )
        )

        let request = try await firstRequest(from: transport)
        let bodyText = try XCTUnwrap(String(data: XCTUnwrap(request.body), encoding: .utf8))
        XCTAssertEqual(
            bodyText,
            #"{"customerData":{"customerId":4440},"entryPoint":"f743aed24a","fallbackAuth":true,"fallbackAuthAmount":100,"#
                + #""methodDescription":"Primary Visa card","source":"ios-sdk","subdomain":"checkout","#
                + #""paymentMethod":{"method":"card","cardexp":"02\/25","cardHolder":"John Doe","#
                + #""cardnumber":"4111111111111111","cardcvv":"123","cardzip":"12345"}}"#
        )
    }

    /// The body's digit members carry ASCII digits only, so a digit-shaped character from another
    /// script is refused rather than sent as the value it resembles.
    func testNonAsciiDigitsDoNotReachTransport() async throws {
        let scenarios: [(PayabliPayInMethodInput, String)] = [
            (PayabliPayInMethodInput.card(PayabliPayInCardData(
                cardNumber: SensitiveDigits.ofString("٤" + String(repeating: "١", count: 15)),
                expiry: "02/25",
                holderName: "John Doe",
                securityCode: SensitiveDigits.ofString("123"),
                postalCode: "12345"
            )), "Card number contains unsupported characters."),
            (PayabliPayInMethodInput.card(PayabliPayInCardData(
                cardNumber: SensitiveDigits.ofString("4111 1111 1111 1111"),
                expiry: "02/25",
                holderName: "John Doe",
                securityCode: SensitiveDigits.ofString(String(repeating: "٤", count: 3)),
                postalCode: "12345"
            )), "CVV contains unsupported characters."),
            (PayabliPayInMethodInput.bankAccount(PayabliPayInBankAccountData(
                accountNumber: SensitiveDigits.ofString(String(repeating: "١", count: 13)),
                accountType: .checking,
                holderName: "John Doe",
                routingNumber: "123456780"
            )), "Account number contains unsupported characters.")
        ]

        for (paymentMethod, expectedMessage) in scenarios {
            let transport = MockTransport(responseBody: "{}")
            let client = PayInPaymentFlowTokenStorageClient(
                transport: transport
            )

            do {
                _ = try await client.addMethod(
                    entryPoint: "entry",
                    paymentMethod: paymentMethod
                )
                XCTFail("Expected validation error")
            } catch let PayabliPayInTokenStorageError.invalidInput(message) {
                XCTAssertEqual(message, expectedMessage)
                let requests = await transport.requests
                XCTAssertTrue(requests.isEmpty)
            } catch {
                XCTFail("Wrong error: \(error)")
            }
        }
    }
}

private func firstRequest(from transport: MockTransport) async throws -> PayabliRequest {
    let requests = await transport.requests
    return try XCTUnwrap(requests.first)
}

private actor MockTransport: PayabliTransport {
    private let statusCode: Int
    private let responseBody: String
    private(set) var requests: [PayabliRequest] = []

    init(statusCode: Int = 200, responseBody: String) {
        self.statusCode = statusCode
        self.responseBody = responseBody
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        // It stands for the service, so every call has reached the HTTP layer.
        PayabliSendMark.current?.set()
        requests.append(request)
        return PayabliResponse(
            statusCode: statusCode, headers: [:], body: Data(responseBody.utf8)
        )
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw PayabliGenericError(type: .unknown, reason: "performV2 is not used")
    }
}
