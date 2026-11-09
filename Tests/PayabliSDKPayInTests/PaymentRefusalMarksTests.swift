@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A refusal made on the device marks the field it names, including when the payment it refused is a retry whose
/// outcome stays unknown.
@MainActor
final class PaymentRefusalMarksTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    private let transport = ScriptedTransport()
    private lazy var flow = PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport)

    func testARefusalMadeBeforeSendingMarksTheFieldItNames() {
        let refusal = PayabliPayInError.InvalidInput(field: "paymentMethod.cardnumber", reason: "Card number is invalid.")

        XCTAssertEqual(PayabliPayInRejectedFields.fields(in: refusal), [.cardNumber])
        XCTAssertEqual(PayabliPayInRejectedFields.fields(in: PayabliPayInError.InvalidInput(field: nil, reason: "x")), [])
        XCTAssertEqual(PayabliPayInRejectedFields.fields(in: PayabliPayInError.InvalidInput(field: "entryPoint", reason: "x")), [])
    }

    func testAnUnknownOutcomeKeepsTheMarksOfTheRefusalItWraps() {
        let refusal = PayabliPayInError.InvalidInput(field: "paymentMethod.cardnumber", reason: "Card number is invalid.")
        let unsettled = PayabliPayInError.Unsettled(cause: refusal, paymentReference: "p1")
        let retyped = PayabliPayInError.Unsettled(unsettled, type: .retryRefused, paymentReference: "p1")

        XCTAssertEqual(PayabliPayInRejectedFields.fields(in: unsettled), [.cardNumber])
        XCTAssertEqual(PayabliPayInRejectedFields.fields(in: retyped), [.cardNumber])
        XCTAssertFalse(String(reflecting: unsettled.underlying).contains("cardnumber"), "the cause stays redacted")
    }

    func testAHeldRetryRefusedOverAFieldDrawsTheMarkAndTheUnknownOutcome() async throws {
        let refusal = PayabliPayInError.InvalidInput(field: "paymentMethod.cardnumber", reason: "Card number is invalid.")
        transport.script = [.lost, .refusedBeforeHandOff(refusal)]
        let viewModel = try await formRetryingAnUnknownPayment()

        let error = await PayInFixture.failure { _ = try await viewModel.submit() }

        XCTAssertTrue(error is PayabliPayInError.Unsettled, "Wrong error: \(String(describing: error))")
        XCTAssertEqual(viewModel.rejectedFields, [.cardNumber])
        XCTAssertEqual(viewModel.failureMessage, Self.outcomeUnknown)
    }

    func testAHeldRetryLeftUnansweredDrawsTheUnknownOutcomeAndNoMark() async throws {
        transport.script = [.lost, .lost]
        let viewModel = try await formRetryingAnUnknownPayment()

        let error = await PayInFixture.failure { _ = try await viewModel.submit() }

        XCTAssertTrue(error is PayabliPayInError.Unsettled, "Wrong error: \(String(describing: error))")
        XCTAssertEqual(viewModel.rejectedFields, [])
        XCTAssertEqual(viewModel.failureMessage, Self.outcomeUnknown)
    }

    func testAHeldRetryRefusedOverAFieldOffScreenDrawsTheUnknownOutcomeAndNoMark() async throws {
        let refusal = PayabliPayInError.InvalidInput(field: "customerData.billingEmail", reason: "Email is invalid.")
        transport.script = [.lost, .refusedBeforeHandOff(refusal)]
        let viewModel = try await formRetryingAnUnknownPayment()

        _ = await PayInFixture.failure { _ = try await viewModel.submit() }

        XCTAssertEqual(viewModel.rejectedFields, [])
        XCTAssertEqual(viewModel.failureMessage, Self.outcomeUnknown)
    }

    // MARK: - Fixtures

    private static let outcomeUnknown = PayabliPayInFailureMessage.text(for: .outcomeUnknown, operation: .capture)

    /// A form whose first send was lost, handed the same payment again as a retry and filled again.
    private func formRetryingAnUnknownPayment() async throws -> PayabliPayInViewModel {
        let configuration = PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        let payment = PayabliPayInPaymentDetails(totalAmount: 12.34)
        let viewModel = PayabliPayInViewModel(
            component: flow,
            operation: .capture(PayabliPayInRequestConfiguration(paymentDetails: payment, paymentReference: "p1")),
            configuration: configuration
        )
        fillCard(viewModel)
        _ = await PayInFixture.failure { _ = try await viewModel.submit() }
        viewModel.update(
            component: flow,
            operation: .capture(PayabliPayInRequestConfiguration(
                paymentDetails: payment,
                paymentReference: "p1",
                attempt: .retry
            )),
            configuration: configuration,
            labels: PayabliPayInFormLabels()
        )
        fillCard(viewModel)
        return viewModel
    }

    private func fillCard(_ viewModel: PayabliPayInViewModel) {
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "12/30"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "12345"
    }
}
