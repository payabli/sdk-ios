@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

@MainActor
final class PaymentFormRefusalTests: XCTestCase {
    func testAnAmountRefusalKeepsTheCardFields() async throws {
        let viewModel = form(
            on: RecordingTransport(),
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 1.00, serviceFee: 1.00, currency: "USD"),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        fillCard(viewModel)

        do {
            _ = try await viewModel.submit()
            XCTFail("a fee equal to the total is refused")
        } catch PayabliPayInError.invalidInput {}
        XCTAssertEqual(viewModel.cardNumber.filter(\.isNumber), "4111111111111111")
        XCTAssertEqual(viewModel.cardExpiration, "02/27")
        XCTAssertEqual(viewModel.cardCvv, "999")
    }

    func testAnAmountRefusalKeepsTheBankFields() async throws {
        let viewModel = form(
            on: RecordingTransport(),
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 0.30, surchargeFee: 0.50, currency: "USD"),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.bankAccount], defaultMethod: .bankAccount)
        )
        viewModel.accountHolder = "Jane Business"
        viewModel.routingNumber = "123456780"
        viewModel.accountNumber = "1111111111"

        do {
            _ = try await viewModel.submit()
            XCTFail("a surcharge above the total is refused")
        } catch PayabliPayInError.invalidInput {}
        XCTAssertEqual(viewModel.routingNumber, "123456780")
        XCTAssertEqual(viewModel.accountNumber, "1111111111")
    }

    func testAMissingRequiredFieldIsRefusedBeforeAnythingIsSent() async throws {
        let transport = RecordingTransport()
        let viewModel = form(
            on: transport,
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34, currency: "USD"),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card],
                defaultMethod: .card,
                requiredFields: [.firstName]
            )
        )
        fillCard(viewModel)

        do {
            _ = try await viewModel.submit()
            XCTFail("a missing first name is refused")
        } catch let PayabliPayInError.invalidInput(reason) {
            XCTAssertEqual(reason, "First name is required.")
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(viewModel.cardNumber.filter(\.isNumber), "4111111111111111")
        XCTAssertEqual(viewModel.cardCvv, "999")
    }

    private func form(
        on transport: RecordingTransport,
        paymentDetails: PayabliPayInPaymentDetails,
        configuration: PayabliPayInFormConfiguration
    ) -> PayabliPayInViewModel {
        PayabliPayInViewModel(
            component: PayabliPayIn(
                entryPoint: "entry",
                environment: .sandbox,
                transport: transport,
                operation: .capture,
                requestConfiguration: PayabliPayInRequestConfiguration(paymentDetails: paymentDetails)
            ),
            configuration: configuration
        )
    }

    private func fillCard(_ viewModel: PayabliPayInViewModel) {
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/27"
        viewModel.cardCvv = "999"
        viewModel.cardZip = "12345"
    }
}

/// Records every request and answers none, for tests whose submission must not be sent.
private actor RecordingTransport: PayabliTransport {
    private(set) var requests: [PayabliRequest] = []

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        requests.append(request)
        throw PayabliGenericError(type: .networkError, reason: "not answered in this test")
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        requests.append(request)
        throw PayabliGenericError(type: .networkError, reason: "not answered in this test")
    }
}
