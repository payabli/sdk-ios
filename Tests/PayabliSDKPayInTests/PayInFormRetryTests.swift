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

    func testAnUpdateToAnEmptyPaymentReferenceIsTheOperationSubmitted() async {
        transport.script = [.approved]
        let configuration = PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        let payment = PayabliPayInPaymentDetails(totalAmount: 12.34)
        let viewModel = PayabliPayInViewModel(
            component: flow,
            operation: .capture(PayabliPayInRequestConfiguration(paymentDetails: payment)),
            configuration: configuration
        )
        viewModel.update(
            component: flow,
            operation: .capture(PayabliPayInRequestConfiguration(paymentDetails: payment, paymentReference: "")),
            configuration: configuration,
            labels: PayabliPayInFormLabels()
        )
        fillCard(viewModel)

        let error = await PayInFixture.failure { _ = try await viewModel.submit() }

        guard error is PayabliPayInError.InvalidInput else { return XCTFail("Wrong error: \(String(describing: error))") }
        XCTAssertTrue(transport.sentKeys.isEmpty, "the blank reference was refused before sending")
    }

    func testATapSubmitsTheOperationTheFormHoldsNow() async throws {
        transport.script = [.approved]
        let configuration = PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        let payment = PayabliPayInPaymentDetails(totalAmount: 12.34)
        let viewModel = PayabliPayInViewModel(
            component: flow,
            operation: .capture(PayabliPayInRequestConfiguration(paymentDetails: payment)),
            configuration: configuration
        )
        fillCard(viewModel)
        var failures: [any PayabliError] = []
        var completions = 0
        let form = PayabliPayInForm(
            viewModel: viewModel,
            operation: .capture(PayabliPayInRequestConfiguration(paymentDetails: payment, paymentReference: "")),
            onCompleted: { _ in completions += 1 },
            onFailed: { failures.append($0) },
            onMethodChanged: { _ in }
        )

        form.submitForOutcome()
        let deadline = Date().addingTimeInterval(5)
        while failures.isEmpty, completions == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(completions, 0)
        guard try XCTUnwrap(failures.first) is PayabliPayInError.InvalidInput else {
            return XCTFail("Wrong error: \(failures)")
        }
        XCTAssertTrue(transport.sentKeys.isEmpty, "the blank reference was refused before sending")
    }

    private func fillCard(_ viewModel: PayabliPayInViewModel) {
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "12/30"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "12345"
    }
}
