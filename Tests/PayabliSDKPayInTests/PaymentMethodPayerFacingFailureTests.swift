import Foundation
@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A failed submission shows the payer its category's message — the host's wording where it supplied
/// any — and never the error's own text, while the failure the host receives is the one the flow
/// threw: the payment's own error, the store's, or a core failure, each keeping its category.
@MainActor
final class PaymentMethodPayerFacingFailureTests: XCTestCase {
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
        XCTAssertNil(viewModel.failureMessage)
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
        XCTAssertEqual(viewModel.failureMessage, "The payment couldn't be completed.")
    }

    // MARK: - The host's own wording

    func testAHostsDeclinedMessageReplacesTheDefaultForItsCategory() async {
        await assertDraws(
            "That card didn't work.",
            on: flowOnTransport(MockPaymentCaptureTransport(statusCode: 402, responseBody: Self.declineBody)),
            category: .declined,
            labels: PayabliPayInFormLabels(declinedMessage: "That card didn't work.")
        )
    }

    func testAHostsRetryMessageReplacesTheDefaultForItsCategory() async {
        await assertDraws(
            "It's busy right now. Try once more.",
            on: flowOnTransport(RecordingIdempotencyTransport(body: Data(), status: 429)),
            category: .retryLater,
            labels: PayabliPayInFormLabels(retryLaterMessage: "It's busy right now. Try once more.")
        )
    }

    func testAHostsUnknownOutcomeMessageReplacesTheDefaultForItsCategory() async {
        await assertDraws(
            "We can't tell whether that went through. Check before paying again.",
            on: flowOnTransport(RecordingIdempotencyTransport(failure: URLError(.notConnectedToInternet))),
            category: .outcomeUnknown,
            labels: PayabliPayInFormLabels(
                outcomeUnknownMessage: "We can't tell whether that went through. Check before paying again."
            )
        )
    }

    func testAHostsOtherMessageReplacesTheDefaultForEveryOtherCategory() async {
        await assertDraws(
            "Something went wrong on our side.",
            on: flowWhoseTokenProviderThrows(),
            category: .credential,
            labels: PayabliPayInFormLabels(otherMessage: "Something went wrong on our side.")
        )
    }

    func testABlankFailureLabelFallsBackToTheDefault() async {
        await assertDraws(
            "The payment was declined. Try another payment method.",
            on: flowOnTransport(MockPaymentCaptureTransport(statusCode: 402, responseBody: Self.declineBody)),
            category: .declined,
            labels: PayabliPayInFormLabels(declinedMessage: "   ")
        )
    }

    // MARK: - The opt-out

    func testTheOptOutHidesTheFormLevelMessageAndTheFailureStillReachesTheHost() async {
        let viewModel = filledForm(
            on: flowOnTransport(MockPaymentCaptureTransport(statusCode: 402, responseBody: Self.declineBody)),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card],
                defaultMethod: .card,
                showsFailureMessage: false
            )
        )

        do {
            _ = try await viewModel.submit()
            XCTFail("the submission fails")
        } catch let error as any PayabliError {
            XCTAssertEqual(error.category, .declined)
            XCTAssertNil(viewModel.failureMessage)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testTheOptOutLeavesAFieldAMarkedFailureStillMarks() async {
        let viewModel = filledForm(
            on: flowOnTransport(MockPaymentCaptureTransport(
                statusCode: 400,
                responseBody: Self.refusal(naming: ["paymentMethod.cardnumber", "entryPoint"])
            )),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card],
                defaultMethod: .card,
                showsFailureMessage: false
            )
        )

        _ = try? await viewModel.submit()

        XCTAssertEqual(viewModel.rejectedFields, [.cardNumber])
        XCTAssertNil(viewModel.failureMessage)
    }

    /// The opt-out is a property of the configuration the form holds now, so a change that withdraws
    /// it withdraws the message a failure already drew; the marks stay, because a marked field is the
    /// whole answer.
    func testAnUpdateThatWithdrawsTheOptOutTakesTheDrawnMessageWithIt() async {
        let flow = flowOnTransport(MockPaymentCaptureTransport(statusCode: 402, responseBody: Self.declineBody))
        let viewModel = filledForm(on: flow)

        _ = try? await viewModel.submit()
        XCTAssertEqual(viewModel.failureMessage, "The payment was declined. Try another payment method.")

        viewModel.update(
            component: flow,
            operation: .capture,
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card],
                defaultMethod: .card,
                showsFailureMessage: false
            ),
            labels: PayabliPayInFormLabels()
        )

        XCTAssertNil(viewModel.failureMessage)
    }

    /// The wording a drawn message follows is the wording the form holds now, so a changed failure
    /// label redraws the message the failure already drew.
    func testAChangedFailureLabelRedrawsTheDrawnMessage() async {
        let flow = flowOnTransport(MockPaymentCaptureTransport(statusCode: 402, responseBody: Self.declineBody))
        let viewModel = filledForm(on: flow)

        _ = try? await viewModel.submit()
        XCTAssertEqual(viewModel.failureMessage, "The payment was declined. Try another payment method.")

        viewModel.update(
            component: flow,
            operation: .capture,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card),
            labels: PayabliPayInFormLabels(declinedMessage: "That card didn't work.")
        )

        XCTAssertEqual(viewModel.failureMessage, "That card didn't work.")
    }

    func testABlankFailureLabelFallsBackToTheSDKsOwnText() async {
        let flow = flowOnTransport(MockPaymentCaptureTransport(statusCode: 402, responseBody: Self.declineBody))
        let viewModel = filledForm(on: flow)

        _ = try? await viewModel.submit()
        viewModel.update(
            component: flow,
            operation: .capture,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card),
            labels: PayabliPayInFormLabels(declinedMessage: "That card didn't work.")
        )
        XCTAssertEqual(viewModel.failureMessage, "That card didn't work.")

        viewModel.update(
            component: flow,
            operation: .capture,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card),
            labels: PayabliPayInFormLabels(declinedMessage: "   ")
        )

        XCTAssertEqual(viewModel.failureMessage, "The payment was declined. Try another payment method.")
    }

    /// A redraw keeps the failure's own category, so a changed label for another category leaves
    /// the drawn message alone.
    func testAChangedLabelForAnotherCategoryLeavesTheDrawnMessage() async {
        let flow = flowOnTransport(MockPaymentCaptureTransport(statusCode: 402, responseBody: Self.declineBody))
        let viewModel = filledForm(on: flow)

        _ = try? await viewModel.submit()

        viewModel.update(
            component: flow,
            operation: .capture,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card),
            labels: PayabliPayInFormLabels(retryLaterMessage: "It's busy right now. Try once more.")
        )

        XCTAssertEqual(viewModel.failureMessage, "The payment was declined. Try another payment method.")
    }

    // MARK: - The failure the host receives

    /// What the view model's `submit()` throws is what the form's `onFailed` hands the host: the
    /// button's task forwards the failure unchanged, so each pin mounts the real flow and asserts on
    /// the error it throws.
    func testAPaymentsFailureReachesTheHostAsThePayInErrorTheFlowThrew() async {
        let viewModel = filledForm(
            on: flowOnTransport(MockPaymentCaptureTransport(statusCode: 402, responseBody: Self.declineBody))
        )

        do {
            _ = try await viewModel.submit()
            XCTFail("the submission fails")
        } catch let error as PayabliPayInError {
            guard case .transactionFailed = error else { return XCTFail("Wrong case: \(error)") }
            XCTAssertEqual(error.type, .paymentDeclined)
            XCTAssertEqual(error.category, .declined)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testAStoresRefusalReachesTheHostAsTheStoresOwnError() async {
        let viewModel = filledStoreForm(
            on: flowStoring(MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.storeRefusalBody))
        )

        do {
            _ = try await viewModel.submit()
            XCTFail("the store fails")
        } catch let error as PayabliPayInTokenStorageError {
            guard case .saveFailed = error else { return XCTFail("Wrong case: \(error)") }
            XCTAssertEqual(error.category, .declined)
            XCTAssertEqual(
                viewModel.failureMessage,
                "This payment method couldn't be saved. Try another one.",
                "the message and the error carry one category"
            )
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testAStoresRefusedRequestReachesTheHostAsTheCoreValidationErrorTheFlowThrew() async {
        let viewModel = filledStoreForm(
            on: flowStoring(MockPaymentCaptureTransport(statusCode: 400, responseBody: Self.storeBadRequestBody))
        )

        do {
            _ = try await viewModel.submit()
            XCTFail("the store fails")
        } catch let error as PayabliPaymentError {
            guard case .validation = error else { return XCTFail("Wrong case: \(error)") }
            XCTAssertEqual(error.category, .invalidRequest)
            XCTAssertEqual(
                viewModel.failureMessage,
                "The payment method couldn't be saved.",
                "a refused store reads as refused, never as open"
            )
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testAStoresServerFailureReachesTheHostAsTheCoreServerErrorTheFlowThrew() async {
        let viewModel = filledStoreForm(
            on: flowStoring(MockPaymentCaptureTransport(statusCode: 500, responseBody: Self.storeServerErrorBody))
        )

        do {
            _ = try await viewModel.submit()
            XCTFail("the store fails")
        } catch let error as PayabliPaymentError {
            guard case .server = error else { return XCTFail("Wrong case: \(error)") }
            XCTAssertEqual(error.category, .outcomeUnknown)
            XCTAssertEqual(
                viewModel.failureMessage,
                "The payment method couldn't be saved.",
                "a save moves no money, so its failure never says a payment may have gone through"
            )
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - Fixtures

    /// Submits a filled form on `flow`, and asserts the thrown error is the real failure, the form draws
    /// `message`, and nothing the form holds carries the error's own text.
    private func assertDraws(
        _ message: String,
        on flow: PayabliPayIn,
        category: PayabliErrorCategory,
        labels: PayabliPayInFormLabels = PayabliPayInFormLabels(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let viewModel = filledForm(on: flow, labels: labels)

        do {
            _ = try await viewModel.submit()
            XCTFail("the submission fails", file: file, line: line)
        } catch let error as any PayabliError {
            XCTAssertEqual(error.category, category, file: file, line: line)
            XCTAssertEqual(viewModel.failureMessage, message, file: file, line: line)
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

    private func filledForm(
        on component: PayabliPayIn,
        labels: PayabliPayInFormLabels = PayabliPayInFormLabels(),
        configuration: PayabliPayInFormConfiguration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            defaultMethod: .card
        )
    ) -> PayabliPayInViewModel {
        let viewModel = PayabliPayInViewModel(
            component: component,
            operation: .capture,
            configuration: configuration,
            labels: labels
        )
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/30"
        viewModel.cardCvv = "123"
        viewModel.cardZip = "33139"
        XCTAssertTrue(viewModel.canSubmit)
        return viewModel
    }

    private func filledStoreForm(on component: PayabliPayIn) -> PayabliPayInViewModel {
        let viewModel = PayabliPayInViewModel(
            component: component,
            operation: .storePaymentMethod,
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

    private func flowStoring(_ transport: any PayabliTransport) -> PayabliPayIn {
        PayabliPayIn(
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            operation: .storePaymentMethod
        )
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

    private static let storeServerErrorBody = """
    {
      "isSuccess": false,
      "responseText": "Error"
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
