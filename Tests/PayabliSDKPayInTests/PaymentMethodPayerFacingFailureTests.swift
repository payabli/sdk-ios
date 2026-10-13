import Foundation
@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A failure the payer cannot fix reaches the host through the thrown error and leaves the form
/// drawing nothing about it.
@MainActor
final class PaymentMethodPayerFacingFailureTests: XCTestCase {
    func testATokenProviderFailureReachesTheCallerAndDrawsNothing() async throws {
        let viewModel = filledForm(on: flowWhoseTokenProviderThrows())

        do {
            _ = try await viewModel.submit()
            XCTFail("a token provider that throws fails the submission")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.type, .tokenProviderFailed)
            let held = Self.storedValues(of: viewModel)
            XCTAssertFalse(held.contains(error.reason), "the form holds the failure's text")
            XCTAssertFalse(held.contains(error.detail ?? error.reason), "the form holds the failure's text")
        }
        XCTAssertEqual(DrawnForm(viewModel), DrawnForm.afterAFailureNamingNoField)
    }

    func testADeclineANetworkFailureAndATokenFailureLookTheSameToThePayer() async {
        let decline = flowOnTransport(MockPaymentCaptureTransport(statusCode: 402, responseBody: Self.declineBody))
        let network = flowOnTransport(OfflineTransport())
        let token = flowWhoseTokenProviderThrows()

        var drawn: [DrawnForm] = []
        for flow in [decline, network, token] {
            let viewModel = filledForm(on: flow)
            _ = try? await viewModel.submit()
            drawn.append(DrawnForm(viewModel))
        }

        XCTAssertEqual(drawn[0], DrawnForm.afterAFailureNamingNoField, "decline")
        XCTAssertEqual(drawn[1], DrawnForm.afterAFailureNamingNoField, "network")
        XCTAssertEqual(drawn[2], DrawnForm.afterAFailureNamingNoField, "token provider")
    }

    // MARK: - Fixtures

    /// Every stored property of the form's model, rendered, so an assertion can sweep it for text the
    /// form must not hold.
    private static func storedValues(of viewModel: PayabliPayInViewModel) -> String {
        Mirror(reflecting: viewModel).children.map { String(describing: $0.value) }.joined(separator: "\n")
    }

    /// Everything the form draws once a submission has failed.
    private struct DrawnForm: Equatable {
        let rejectedFields: Set<PayabliPayInField>
        let cardholderName: String
        let cardNumber: String
        let cardExpiration: String
        let cardCvv: String
        let cardZip: String
        let canSubmit: Bool
        let isSubmitting: Bool

        @MainActor
        init(_ viewModel: PayabliPayInViewModel) {
            rejectedFields = viewModel.rejectedFields
            cardholderName = viewModel.cardholderName
            cardNumber = viewModel.cardNumber
            cardExpiration = viewModel.cardExpiration
            cardCvv = viewModel.cardCvv
            cardZip = viewModel.cardZip
            canSubmit = viewModel.canSubmit
            isSubmitting = viewModel.isSubmitting
        }

        private init(
            rejectedFields: Set<PayabliPayInField>,
            cardholderName: String,
            cardNumber: String,
            cardExpiration: String,
            cardCvv: String,
            cardZip: String,
            canSubmit: Bool,
            isSubmitting: Bool
        ) {
            self.rejectedFields = rejectedFields
            self.cardholderName = cardholderName
            self.cardNumber = cardNumber
            self.cardExpiration = cardExpiration
            self.cardCvv = cardCvv
            self.cardZip = cardZip
            self.canSubmit = canSubmit
            self.isSubmitting = isSubmitting
        }

        /// No field marked, the card's secrets cleared, and the payer's name and postal code kept.
        static let afterAFailureNamingNoField = DrawnForm(
            rejectedFields: [],
            cardholderName: "Jane Doe",
            cardNumber: "",
            cardExpiration: "",
            cardCvv: "",
            cardZip: "33139",
            canSubmit: false,
            isSubmitting: false
        )
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
        paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10, currency: "USD"),
        idempotencyKey: "idem-payer-facing"
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
            session: PayabliSession(config: config),
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
}

private actor OfflineTransport: PayabliTransport {
    func perform(_: PayabliRequest) async throws -> PayabliResponse {
        throw URLError(.notConnectedToInternet)
    }

    func performV2<T: Decodable & Sendable>(
        _: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw URLError(.notConnectedToInternet)
    }
}
