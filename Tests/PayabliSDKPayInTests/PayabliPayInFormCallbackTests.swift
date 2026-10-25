@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import SwiftUI
import UIKit
import XCTest

/// The form's callbacks: the method events a change to the drawn method reports and the ones it
/// must not, the sheet's forwarding of them, and the outcome a submission hands its host, driven
/// through submitForOutcome() — the form's button hosts no UIKit button a test could press.
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

    func testAnApprovedCaptureReportsOnePaymentAndNothingElse() async {
        let recorder = CallbackRecorder()
        let form = filledBankForm(
            on: captureFlow(on: MockPaymentCaptureTransport(responseBody: Self.approvedCaptureBody)),
            operation: .capture,
            recorder: recorder
        )

        form.submitForOutcome()
        await waitUntil { !recorder.successes.isEmpty || !recorder.failures.isEmpty }

        XCTAssertEqual(recorder.failures.count, 0, "an approved capture reports no failure")
        guard recorder.successes.count == 1 else {
            return XCTFail("one completion, not \(recorder.successes.count)")
        }
        guard case let .payment(result) = recorder.successes[0] else {
            return XCTFail("Wrong case: \(recorder.successes[0])")
        }
        XCTAssertEqual(result.kind, .transaction)
        XCTAssertEqual(result.code, "A0000")
    }

    /// A failure the SDK names reaches the host as the failure the flow threw, never as the
    /// unknown-error wrapper, and nothing else reaches it.
    func testADeclinedCaptureReportsTheTypedFailureTheFlowThrew() async {
        let recorder = CallbackRecorder()
        let form = filledBankForm(
            on: captureFlow(
                on: MockPaymentCaptureTransport(statusCode: 402, responseBody: Self.declineBody)
            ),
            operation: .capture,
            recorder: recorder
        )

        form.submitForOutcome()
        await waitUntil { !recorder.successes.isEmpty || !recorder.failures.isEmpty }

        XCTAssertEqual(recorder.successes.count, 0, "a declined capture reports no completion")
        guard recorder.failures.count == 1 else {
            return XCTFail("one failure, not \(recorder.failures.count)")
        }
        let failure = recorder.failures[0]
        guard case PayabliPayInError.transactionFailed = failure else {
            return XCTFail("Wrong error: \(failure)")
        }
        XCTAssertEqual(failure.type, .paymentDeclined)
        XCTAssertEqual(failure.category, .declined)
    }

    func testAStoredSubmissionReportsOneStoredMethodAndNothingElse() async {
        let recorder = CallbackRecorder()
        let form = filledBankForm(
            on: storeFlow(
                on: MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.storedMethodBody)
            ),
            operation: .storePaymentMethod,
            recorder: recorder
        )

        form.submitForOutcome()
        await waitUntil { !recorder.successes.isEmpty || !recorder.failures.isEmpty }

        XCTAssertEqual(recorder.failures.count, 0, "a stored submission reports no failure")
        guard recorder.successes.count == 1 else {
            return XCTFail("one completion, not \(recorder.successes.count)")
        }
        guard case let .method(stored) = recorder.successes[0] else {
            return XCTFail("Wrong case: \(recorder.successes[0])")
        }
        XCTAssertEqual(stored.storedMethodId, "stored-123")
    }

    func testAStoresRefusalReportsTheStoresOwnFailureItThrew() async {
        let recorder = CallbackRecorder()
        let form = filledBankForm(
            on: storeFlow(
                on: MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.storeRefusalBody)
            ),
            operation: .storePaymentMethod,
            recorder: recorder
        )

        form.submitForOutcome()
        await waitUntil { !recorder.successes.isEmpty || !recorder.failures.isEmpty }

        XCTAssertEqual(recorder.successes.count, 0, "a refused store reports no completion")
        guard recorder.failures.count == 1 else {
            return XCTFail("one failure, not \(recorder.failures.count)")
        }
        let failure = recorder.failures[0]
        guard case PayabliPayInTokenStorageError.saveFailed = failure else {
            return XCTFail("Wrong error: \(failure)")
        }
        XCTAssertEqual(failure.category, .declined)
    }

    func testAStoresRefusedRequestReportsTheCoreValidationFailureItThrew() async {
        let recorder = CallbackRecorder()
        let form = filledBankForm(
            on: storeFlow(
                on: MockPaymentCaptureTransport(statusCode: 400, responseBody: Self.storeBadRequestBody)
            ),
            operation: .storePaymentMethod,
            recorder: recorder
        )

        form.submitForOutcome()
        await waitUntil { !recorder.successes.isEmpty || !recorder.failures.isEmpty }

        XCTAssertEqual(recorder.successes.count, 0, "a refused store reports no completion")
        guard recorder.failures.count == 1 else {
            return XCTFail("one failure, not \(recorder.failures.count)")
        }
        let failure = recorder.failures[0]
        guard case PayabliPaymentError.validation = failure else {
            return XCTFail("Wrong error: \(failure)")
        }
        XCTAssertEqual(failure.category, .invalidRequest)
    }

    /// A failure outside the catalog, arriving raw from the store route, is answered as the
    /// unknown-error shape: the catalog's reason, the failing type's name, its message never.
    func testAnUnexpectedFailureIsReportedAsTheUnknownShapeAlone() async {
        let cause = URLError(.userAuthenticationRequired)
        let recorder = CallbackRecorder()
        let form = filledBankForm(
            on: storeFlow(on: RecordingIdempotencyTransport(failure: cause)),
            operation: .storePaymentMethod,
            recorder: recorder
        )

        form.submitForOutcome()
        await waitUntil { !recorder.successes.isEmpty || !recorder.failures.isEmpty }

        XCTAssertEqual(recorder.successes.count, 0, "a failed store reports no completion")
        guard recorder.failures.count == 1 else {
            return XCTFail("one failure, not \(recorder.failures.count)")
        }
        guard let reported = recorder.failures[0] as? PayabliGenericError else {
            return XCTFail("Wrong error: \(recorder.failures[0])")
        }
        XCTAssertEqual(reported.type, .unknown)
        XCTAssertEqual(reported.reason, PayabliErrorType.unknown.message)
        XCTAssertEqual(reported.underlying as? RedactedCause, RedactedCause(cause))
        XCTAssertFalse(
            String(describing: reported).contains(cause.localizedDescription),
            "the failing error's message never reaches the host"
        )
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

    /// A bank form the payer filled, bound to the state the payer's typing left, so a case drives
    /// the form's own submission path with the values a submission needs.
    private func filledBankForm(
        on payIn: PayabliPayIn,
        operation: PayabliPayInOperation,
        recorder: CallbackRecorder
    ) -> PayabliPayInForm {
        let viewModel = PayabliPayInViewModel(
            component: payIn,
            operation: operation,
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount
            )
        )
        viewModel.accountHolder = "Jane Doe"
        viewModel.routingNumber = "123456780"
        viewModel.accountNumber = "1111111111111"

        let form = PayabliPayInForm(
            viewModel: viewModel,
            onCompleted: { recorder.successes.append($0) },
            onFailed: { recorder.failures.append($0) },
            onMethodChanged: { recorder.methods.append($0) }
        )
        XCTAssertTrue(form.viewModel.canSubmit, "the filled bank form can submit")
        return form
    }

    /// A capture flow on a transport the cases answer from, carrying the request the form submits.
    private func captureFlow(on transport: any PayabliTransport) -> PayabliPayIn {
        PayabliPayIn(
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            operation: .capture,
            requestConfiguration: PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10, currency: "USD")
            )
        )
    }

    /// A store flow on a transport the cases answer from.
    private func storeFlow(on transport: any PayabliTransport) -> PayabliPayIn {
        PayabliPayIn(
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            operation: .storePaymentMethod
        )
    }

    /// Runs the main actor, bounded, until the condition holds or the timeout does, so a case can
    /// await the task a submission runs.
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
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

    private static let storeRefusalBody = """
    {
      "responseText": "Declined",
      "isSuccess": false,
      "responseData": {
        "resultCode": 2,
        "resultText": "Account validation failed"
      }
    }
    """

    private static let storeBadRequestBody = """
    {
      "isSuccess": false,
      "responseText": "Error",
      "responseCode": 6000,
      "responseData": {
        "explanation": "Invalid Card",
        "todoAction": "Please check your card details and try again."
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
