@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import SwiftUI
import UIKit
import XCTest

/// The form's callbacks: the method events a change to the drawn method reports and the ones it
/// must not, the sheet's forwarding of them, and the outcome a submission hands its host. A
/// submission is driven through the view model: the form's submit button hosts no UIKit button.
@MainActor
final class PayabliPayInFormCallbackTests: XCTestCase {
    func testTheFormOpensWithoutReportingAMethodChange() throws {
        let recorder = CallbackRecorder()
        let host = PayInUIKitHostingSupport.host(
            form(
                on: flowOnSession(),
                operation: .storePaymentMethod,
                allowedMethods: [.card, .bankAccount],
                defaultMethod: .bankAccount,
                recorder: recorder
            )
        )
        _ = try segmentedControl(afterRendering: host)
        renderUntil(in: host, timeout: 0.5) { !recorder.methods.isEmpty }

        XCTAssertTrue(recorder.methods.isEmpty, "the method the form opens with is not an event")
    }

    func testAWithdrawnMethodReportsTheOneItFallsBackTo() throws {
        let recorder = CallbackRecorder()
        let payIn = flowOnSession()
        let host = PayInUIKitHostingSupport.host(
            form(
                on: payIn,
                operation: .storePaymentMethod,
                allowedMethods: [.card, .bankAccount],
                defaultMethod: .bankAccount,
                recorder: recorder
            )
        )
        _ = try segmentedControl(afterRendering: host)
        XCTAssertTrue(recorder.methods.isEmpty)

        host.rootView = form(
            on: payIn,
            operation: .storePaymentMethod,
            allowedMethods: [.card],
            defaultMethod: .bankAccount,
            recorder: recorder
        )
        renderUntil(in: host) { recorder.methods.count == 1 }

        XCTAssertEqual(recorder.methods, [.card], "the withdrawal reports the method the form falls back to, once")
    }

    func testARestoredAlternativeIsNotReportedAsAChange() throws {
        let recorder = CallbackRecorder()
        let payIn = flowOnSession()
        let host = PayInUIKitHostingSupport.host(
            form(
                on: payIn,
                operation: .storePaymentMethod,
                allowedMethods: [.card, .bankAccount],
                defaultMethod: .bankAccount,
                recorder: recorder
            )
        )
        _ = try segmentedControl(afterRendering: host)
        XCTAssertTrue(recorder.methods.isEmpty)

        host.rootView = form(
            on: payIn,
            operation: .storePaymentMethod,
            allowedMethods: [.card],
            defaultMethod: .bankAccount,
            recorder: recorder
        )
        renderUntil(in: host) { recorder.methods.count == 1 }

        host.rootView = form(
            on: payIn,
            operation: .storePaymentMethod,
            allowedMethods: [.card, .bankAccount],
            defaultMethod: .bankAccount,
            recorder: recorder
        )
        renderUntil(in: host, timeout: 0.5) { recorder.methods.count > 1 }

        XCTAssertEqual(
            recorder.methods,
            [.card],
            "the standing method is not reported again when its alternative returns"
        )
    }

    func testAConfigurationChangeThatTouchesNoMethodReportsNothing() throws {
        let recorder = CallbackRecorder()
        let payIn = flowOnSession()
        let host = PayInUIKitHostingSupport.host(
            form(
                on: payIn,
                operation: .storePaymentMethod,
                allowedMethods: [.card, .bankAccount],
                defaultMethod: .bankAccount,
                recorder: recorder
            )
        )
        _ = try segmentedControl(afterRendering: host)

        host.rootView = form(
            on: payIn,
            operation: .storePaymentMethod,
            allowedMethods: [.card, .bankAccount],
            defaultMethod: .bankAccount,
            labels: PayabliPayInFormLabels(fieldLabels: [.accountHolder: "Bank account owner"]),
            recorder: recorder
        )
        renderUntil(in: host) { textField(labelled: "Bank account owner", in: host) != nil }
        renderUntil(in: host, timeout: 0.5) { !recorder.methods.isEmpty }

        XCTAssertTrue(
            recorder.methods.isEmpty,
            "a configuration change that touches no method is not a method event"
        )
    }

    func testTheSheetForwardsTheMethodEventsItsFormReports() throws {
        let recorder = CallbackRecorder()
        let payIn = flowOnSession()
        let host = PayInUIKitHostingSupport.host(
            sheetContent(on: payIn, allowedMethods: [.card, .bankAccount], recorder: recorder)
        )
        _ = try segmentedControl(afterRendering: host)
        renderUntil(in: host, timeout: 0.5) { !recorder.methods.isEmpty }

        XCTAssertTrue(recorder.methods.isEmpty)

        host.rootView = sheetContent(on: payIn, allowedMethods: [.card], recorder: recorder)
        renderUntil(in: host) { recorder.methods.count == 1 }

        XCTAssertEqual(
            recorder.methods,
            [.card],
            "the sheet hands the form's method events to its own host"
        )
    }

    func testATransactionResultRoutesAsAPayment() {
        let result = PayabliPayInResult(
            apiResponse: PayabliPayInAPIResponse(code: "A0000", reason: "Approved")
        )

        let outcome = PayabliPayInFormSuccess(result)

        guard case let .payment(reported) = outcome else { return XCTFail("Wrong case: \(outcome)") }
        XCTAssertEqual(reported, result)
    }

    func testAStoredMethodResultRoutesAsTheStoredMethod() {
        let stored = PayabliPayInStoredMethod(
            storedMethodId: "stored-123",
            method: .card,
            methodReferenceId: "method-123",
            resultCode: 1,
            resultText: "Approved",
            customerId: 4440,
            responseText: "Success"
        )

        let outcome = PayabliPayInFormSuccess(PayabliPayInResult(storedPaymentMethod: stored))

        guard case let .method(reported) = outcome else { return XCTFail("Wrong case: \(outcome)") }
        XCTAssertEqual(reported, stored)
    }

    func testAnApprovedCaptureRoutesAsAPayment() async throws {
        let viewModel = filledBankAccountForm(
            on: PayabliPayIn(
                entryPoint: "entry",
                environment: .sandbox,
                transport: MockPaymentCaptureTransport(responseBody: Self.approvedCaptureBody),
                operation: .capture,
                requestConfiguration: PayabliPayInRequestConfiguration(
                    paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10, currency: "USD")
                )
            ),
            operation: .capture
        )

        let outcome = PayabliPayInFormSuccess(try await viewModel.submit())

        guard case let .payment(result) = outcome else { return XCTFail("Wrong case: \(outcome)") }
        XCTAssertEqual(result.kind, .transaction)
        XCTAssertEqual(result.code, "A0000")
    }

    func testAStoredSubmissionRoutesAsTheStoredMethod() async throws {
        let viewModel = filledBankAccountForm(
            on: PayabliPayIn(
                entryPoint: "entry",
                environment: .sandbox,
                transport: MockPaymentCaptureTransport(
                    statusCode: 200,
                    responseBody: Self.storedMethodBody
                ),
                operation: .storePaymentMethod
            ),
            operation: .storePaymentMethod
        )

        let outcome = PayabliPayInFormSuccess(try await viewModel.submit())

        guard case let .method(stored) = outcome else { return XCTFail("Wrong case: \(outcome)") }
        XCTAssertEqual(stored.storedMethodId, "stored-123")
    }

    func testAnErrorTheSDKDoesNotNameIsReportedAsTheUnknownShape() {
        let cause = URLError(.userAuthenticationRequired)
        let reported = PayabliPayInForm.reportedUnexpectedFailure(cause)

        XCTAssertEqual(reported.type, .unknown)
        XCTAssertEqual(reported.reason, PayabliErrorType.unknown.message)
        XCTAssertNil(reported.detail)
        XCTAssertEqual(reported.underlying as? RedactedCause, RedactedCause(cause))
        XCTAssertFalse(
            String(describing: reported).contains(cause.localizedDescription),
            "the failing error's message never reaches the host"
        )
    }

    // MARK: - Support

    private func form(
        on payIn: PayabliPayIn,
        operation: PayabliPayInOperation,
        allowedMethods: [PayabliPayInMethodType],
        defaultMethod: PayabliPayInMethodType,
        labels: PayabliPayInFormLabels = PayabliPayInFormLabels(),
        recorder: CallbackRecorder
    ) -> PayabliPayInForm {
        PayabliPayInForm(
            payIn: payIn,
            operation: operation,
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: allowedMethods,
                defaultMethod: defaultMethod
            ),
            labels: labels,
            onCompleted: { recorder.successes.append($0) },
            onFailed: { recorder.failures.append($0) },
            onMethodChanged: { recorder.methods.append($0) }
        )
    }

    private func sheetContent(
        on payIn: PayabliPayIn,
        allowedMethods: [PayabliPayInMethodType],
        recorder: CallbackRecorder
    ) -> PayabliPayInSheetContent {
        PayabliPayInSheetContent(
            isPresented: .constant(true),
            payIn: payIn,
            operation: .storePaymentMethod,
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: allowedMethods,
                defaultMethod: .bankAccount
            ),
            labels: PayabliPayInFormLabels(),
            sheetConfiguration: PayabliPayInSheetConfiguration(),
            style: nil,
            onCompleted: { recorder.successes.append($0) },
            onFailed: { recorder.failures.append($0) },
            onMethodChanged: { recorder.methods.append($0) }
        )
    }

    /// A bank form filled the way the payer's typing leaves it, ready to submit.
    private func filledBankAccountForm(
        on component: PayabliPayIn,
        operation: PayabliPayInOperation
    ) -> PayabliPayInViewModel {
        let viewModel = PayabliPayInViewModel(
            component: component,
            operation: operation,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.bankAccount], defaultMethod: .bankAccount)
        )
        viewModel.accountHolder = "Jane Doe"
        viewModel.routingNumber = "123456780"
        viewModel.accountNumber = "1111111111111"
        XCTAssertTrue(viewModel.canSubmit, "the filled bank form can submit")
        return viewModel
    }

    private func textField(
        labelled label: String,
        in host: UIHostingController<PayabliPayInForm>
    ) -> UITextField? {
        host.view.payabliCoverageAllSubviews.compactMap { $0 as? UITextField }.first {
            $0.accessibilityLabel == label
        }
    }

    private func segmentedControl(
        afterRendering host: UIHostingController<some View>
    ) throws -> UISegmentedControl {
        renderUntil(in: host) {
            host.view.payabliCoverageAllSubviews.contains { $0 is UISegmentedControl }
        }
        return try XCTUnwrap(
            host.view.payabliCoverageAllSubviews.compactMap { $0 as? UISegmentedControl }.first,
            "the form draws a segmented method picker"
        )
    }

    /// Runs the main loop, bounded, until the condition holds or the timeout does.
    private func renderUntil(
        in host: UIHostingController<some View>,
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            host.view.setNeedsLayout()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    private static let approvedCaptureBody = """
    {
      "code": "A0000",
      "reason": "Approved",
      "explanation": "Approved by card network or card issuer.",
      "action": "No action required.",
      "data": {
        "paymentTransId": "3040-transaction",
        "gatewayTransId": "gateway-transaction",
        "orderId": "order-123",
        "method": "card",
        "transStatus": 1,
        "paypointId": 3040,
        "totalAmount": 100,
        "netAmount": 95,
        "feeAmount": 5,
        "settlementStatus": 0,
        "operation": "Sale",
        "source": "api",
        "token": null
      },
      "token": null
    }
    """

    private static let storedMethodBody = """
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
}

/// What a form reported to its host, in the order it arrived.
private final class CallbackRecorder {
    var methods: [PayabliPayInMethodType] = []
    var successes: [PayabliPayInFormSuccess] = []
    var failures: [any PayabliError] = []
}
