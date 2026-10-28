@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

@MainActor
final class PaymentFormRefusalTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    func testAnAmountRefusalSendsNothingAndKeepsTheCardFields() async throws {
        let transport = RecordingTransport()
        let viewModel = form(
            on: transport,
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 1.00, serviceFee: 1.00, currency: "USD"),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        fillCard(viewModel)

        do {
            _ = try await viewModel.submit()
            XCTFail("a fee equal to the total is refused")
        } catch let PayabliPayInError.invalidInput(reason) {
            XCTAssertEqual(reason, "Service fee and surcharge must be less than the total amount.")
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
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

    func testARefusalInTheFlowBeforeSendingKeepsTheCardFields() async throws {
        let transport = RecordingTransport()
        let viewModel = form(
            on: transport,
            entryPoint: "  ",
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34, currency: "USD"),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        fillCard(viewModel)

        do {
            _ = try await viewModel.submit()
            XCTFail("a blank entry point is refused")
        } catch let PayabliPayInError.invalidInput(reason) {
            XCTAssertEqual(reason, "Entrypoint is required.")
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(viewModel.cardNumber.filter(\.isNumber), "4111111111111111")
        XCTAssertEqual(viewModel.cardCvv, "999")
    }

    func testAFailureAfterSendingClearsTheCardFields() async throws {
        let transport = RecordingTransport()
        let viewModel = form(
            on: transport,
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34, currency: "USD"),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        fillCard(viewModel)

        do {
            _ = try await viewModel.submit()
            XCTFail("the send fails")
        } catch {}
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(viewModel.cardNumber, "")
        XCTAssertEqual(viewModel.cardExpiration, "")
        XCTAssertEqual(viewModel.cardCvv, "")
    }

    func testAPaymentRefusedWith401OnItsReplayTooKeepsTheCardFields() async throws {
        let http = UnauthorizedTransport()
        let tokens = TokenSequence()
        let config = try PayabliConfig(entryPoint: "entry", environment: .sandbox, tokenProvider: { await tokens.next() })
        let auth = PayabliAuth(config: config)
        let transport = AuthenticatedTransport(base: http, auth: auth, logger: PayabliLogger(category: .network))
        let viewModel = PayabliPayInViewModel(
            component: PayabliPayIn(
                entryPoint: "entry",
                environment: .sandbox,
                transport: transport,
                operation: .capture,
                requestConfiguration: PayabliPayInRequestConfiguration(
                    paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34, currency: "USD")
                )
            ),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        fillCard(viewModel)

        do {
            _ = try await viewModel.submit()
            XCTFail("both sends are refused with 401")
        } catch {}
        let sends = await http.count
        XCTAssertEqual(sends, 2, "the payment and its replay")
        XCTAssertEqual(viewModel.cardNumber.filter(\.isNumber), "4111111111111111")
        XCTAssertEqual(viewModel.cardCvv, "999")
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
        entryPoint: String = "entry",
        paymentDetails: PayabliPayInPaymentDetails,
        configuration: PayabliPayInFormConfiguration
    ) -> PayabliPayInViewModel {
        PayabliPayInViewModel(
            component: PayabliPayIn(
                entryPoint: entryPoint,
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

/// Answers every request 401 after the hand-off, as the service does for a credential it refuses.
private actor UnauthorizedTransport: PayabliTransport {
    private(set) var count = 0

    func perform(_: PayabliRequest) async throws -> PayabliResponse {
        // It stands for the service, so every call has reached the HTTP layer.
        PayabliSendMark.current?.set()
        count += 1
        return PayabliResponse(statusCode: 401, headers: [:], body: Data())
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        _ = try await perform(request)
        throw PayabliGenericError(type: .tokenExpired, reason: "not answered in this test")
    }
}

/// A new token on every call, so a refresh never returns the token just refused.
private actor TokenSequence {
    private var issued = 0

    func next() -> String {
        issued += 1
        return "token-\(issued)"
    }
}

/// Records every request and fails it after the hand-off, so a request that reaches it counts as sent.
private actor RecordingTransport: PayabliTransport {
    private(set) var requests: [PayabliRequest] = []

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        // It stands for the service, so every call has reached the HTTP layer.
        PayabliSendMark.current?.set()
        requests.append(request)
        throw PayabliGenericError(type: .networkError, reason: "not answered in this test")
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        _ = try await perform(request)
        throw PayabliGenericError(type: .networkError, reason: "not answered in this test")
    }
}
