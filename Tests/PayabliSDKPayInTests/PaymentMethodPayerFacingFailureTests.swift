import Foundation
@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A failed submission shows the payer its category's message and never the error's own text, while the
/// thrown error carries the real failure to the host.
@MainActor
final class PaymentMethodPayerFacingFailureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    func testADeclineDrawsTheDeclinedMessage() async {
        await assertDraws(
            "The payment was declined. Try another payment method.",
            on: flowOnTransport(MockPaymentCaptureTransport(statusCode: 402, responseBody: Self.declineBody)),
            category: .declined
        )
    }

    func testARefusalForTooManyRequestsDrawsTheRetryMessage() async {
        await assertDraws(
            "The payment couldn't be completed. Please try again.",
            on: flowOnTransport(RecordingIdempotencyTransport(body: Data(), status: 429)),
            category: .retryLater
        )
    }

    func testANetworkFailureDrawsTheUnknownOutcomeMessage() async {
        await assertDraws(
            "This payment may have gone through. Check before paying again.",
            on: flowOnTransport(RecordingIdempotencyTransport(failure: URLError(.notConnectedToInternet))),
            category: .outcomeUnknown
        )
    }

    func testATokenProviderFailureDrawsTheDefaultMessage() async {
        await assertDraws(
            "The payment couldn't be completed.",
            on: flowWhoseTokenProviderThrows(),
            category: .credential
        )
    }

    func testARefusalNamingAFieldOnScreenMarksItAndDrawsNoMessage() async {
        let viewModel = filledForm(
            on: flowOnTransport(MockPaymentCaptureTransport(
                statusCode: 400,
                responseBody: Self.refusal(naming: ["paymentMethod.cardnumber", "entryPoint"])
            ))
        )

        _ = try? await viewModel.submit()

        XCTAssertEqual(viewModel.rejectedFields, [.cardNumber])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testARefusalNamingOnlyFieldsOffScreenDrawsItsCategoryMessage() async {
        let viewModel = filledForm(
            on: flowOnTransport(MockPaymentCaptureTransport(
                statusCode: 400,
                responseBody: Self.refusal(naming: ["entryPoint", "paymentDetails.totalAmount"])
            ))
        )

        _ = try? await viewModel.submit()

        XCTAssertEqual(viewModel.rejectedFields, [])
        XCTAssertEqual(viewModel.errorMessage, "The payment couldn't be completed.")
    }

    // MARK: - Fixtures

    /// Submits a filled form on `flow`, and asserts the thrown error is the real failure, the form draws
    /// `message`, and nothing the form holds carries the error's own text.
    private func assertDraws(
        _ message: String,
        on flow: PayabliPayIn,
        category: PayabliErrorCategory,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let viewModel = filledForm(on: flow)

        do {
            _ = try await viewModel.submit()
            XCTFail("the submission fails", file: file, line: line)
        } catch let error as any PayabliError {
            XCTAssertEqual(error.category, category, file: file, line: line)
            XCTAssertEqual(viewModel.errorMessage, message, file: file, line: line)
            XCTAssertEqual(viewModel.rejectedFields, [], file: file, line: line)
            let held = Self.storedValues(of: viewModel)
            for text in [error.reason, error.detail].compactMap({ $0 }) where text != message {
                XCTAssertFalse(held.contains(text), "the form holds \"\(text)\"", file: file, line: line)
            }
        } catch {
            XCTFail("Wrong error: \(error)", file: file, line: line)
        }
    }

    /// Every stored property of the form's model, rendered, so an assertion can sweep it for text the
    /// form must not hold.
    private static func storedValues(of viewModel: PayabliPayInViewModel) -> String {
        Mirror(reflecting: viewModel).children.map { String(describing: $0.value) }.joined(separator: "\n")
    }

    private func filledForm(on component: PayabliPayIn) -> PayabliPayInViewModel {
        let viewModel = PayabliPayInViewModel(
            component: component,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/30"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"
        XCTAssertTrue(viewModel.canSubmit)
        return viewModel
    }

    private static let requestConfiguration = PayabliPayInRequestConfiguration(
        paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10, currency: "USD")
    )

    private func flowOnTransport(_ transport: any PayabliTransport) -> PayabliPayIn {
        PayabliPayIn(
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            operation: .capture,
            requestConfiguration: Self.requestConfiguration
        )
    }

    private func flowWhoseTokenProviderThrows() -> PayabliPayIn {
        let config = try! PayabliConfig(
            entryPoint: "entry",
            environment: .sandbox,
            tokenProvider: { throw URLError(.userAuthenticationRequired) }
        )
        return PayabliPayIn(
            session: PayabliSession(config: config, telemetryTransport: DiscardingTelemetryTransport()),
            operation: .capture,
            requestConfiguration: Self.requestConfiguration
        )
    }

    private static let declineBody = """
    {
      "code": "D0200",
      "reason": "Insufficient Funds",
      "explanation": "The card issuer declined the transaction.",
      "action": "Ask for a different payment method.",
      "data": null,
      "token": null
    }
    """

    private static func refusal(naming parameters: [String]) -> String {
        let errors = parameters
            .map { #""\#($0)":[{"message":"Not a valid value.","suggestion":"Check the value."}]"# }
            .joined(separator: ",")
        return """
        {
          "type": "about:blank",
          "title": "Bad Request",
          "status": 400,
          "detail": "Invalid parameter",
          "instance": "/api/v2/MoneyIn/getpaid",
          "code": "E7002",
          "errors": {\(errors)},
          "token": null
        }
        """
    }
}
