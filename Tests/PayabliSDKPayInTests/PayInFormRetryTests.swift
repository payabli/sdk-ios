@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A form whose payment's outcome is unknown, handed the same payment again as a retry.
@MainActor
final class PayInFormRetryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    private let transport = ScriptedTransport()
    private lazy var flow = PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport)

    func testAFormHandedTheSamePaymentAsARetryResendsTheKeyItHeld() async throws {
        transport.script = [.lost, .approved]
        let configuration = PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        let viewModel = PayabliPayInViewModel(
            component: flow,
            operation: .capture(PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34),
                paymentReference: "p1"
            )),
            configuration: configuration
        )
        fillCard(viewModel)
        _ = await PayInFixture.failure { _ = try await viewModel.submit() }

        viewModel.update(
            component: flow,
            operation: .capture(PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34),
                paymentReference: "p1",
                attempt: .retry
            )),
            configuration: configuration,
            labels: PayabliPayInFormLabels()
        )
        fillCard(viewModel)
        _ = try await viewModel.submit()

        XCTAssertEqual(transport.sentKeys.count, 2)
        XCTAssertEqual(transport.sentKeys.first, transport.sentKeys.last, "the retry did not resend the held key")
    }

    private func fillCard(_ viewModel: PayabliPayInViewModel) {
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "12/30"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "12345"
    }
}
