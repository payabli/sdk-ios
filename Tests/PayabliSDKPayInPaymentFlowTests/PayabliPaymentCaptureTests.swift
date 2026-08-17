@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import SwiftUI
import XCTest

@MainActor
final class PayabliPayInPaymentFlowTests: XCTestCase {
    func testCaptureFacadeTracksSubmissionStateAndLastResult() async throws {
        let transport = FacadeTransport(responseBody: """
        {
          "code": "A0000",
          "reason": "Approved",
          "explanation": "Approved.",
          "action": "No action required.",
          "data": {
            "paymentTransId": "trans-1",
            "method": "card",
            "operation": "Sale"
          },
          "token": null
        }
        """)
        let component = PayabliPayInPaymentFlow(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport
        )

        let result = try await component.capture(PayabliPayInPaymentFlowRequest(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 12.34),
            paymentMethod: .stored(PayabliPayInPaymentFlowStoredMethod(
                method: .card,
                storedMethodId: "stored-123"
            ))
        ))

        XCTAssertFalse(component.isSubmitting)
        XCTAssertEqual(component.lastResult?.code, "A0000")
        XCTAssertEqual(result.transaction?.paymentTransId, "trans-1")
        let request = try await firstFacadeRequest(from: transport)
        XCTAssertEqual(request.headers["Authorization"], "Bearer access-token")
        XCTAssertNil(request.headers["requestToken"])
    }

    func testConfigureRebuildsClientWithNewEnvironmentAndEntrypoint() async throws {
        let transport = FacadeTransport(responseBody: """
        {
          "code": "A0000",
          "reason": "Approved",
          "explanation": "Approved.",
          "action": "No action required.",
          "data": { "paymentTransId": "trans-2" },
          "token": null
        }
        """)
        let component = PayabliPayInPaymentFlow(
            accessToken: "access-token",
            entryPoint: "old-entry",
            environment: .sandbox,
            transport: transport
        )

        component.configure(config: PayabliConfig(
            accessToken: "unused",
            entryPoint: "new-entry",
            environment: .qa
        ))

        _ = try await component.capture(PayabliPayInPaymentFlowRequest(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 10),
            paymentMethod: .cash
        ))

        XCTAssertEqual(component.entryPoint, "new-entry")
        XCTAssertEqual(component.environment, .qa)
        let request = try await firstFacadeRequest(from: transport)
        let body = try parseFacadeBody(request)
        XCTAssertEqual(body["entryPoint"] as? String, "new-entry")
    }

    func testConfiguredSubmitUsesAuthorizeOperation() async throws {
        let transport = FacadeTransport(responseBody: """
        {
          "code": "A0002",
          "reason": "Authorized",
          "explanation": "Authorized.",
          "action": "Capture later.",
          "data": {
            "paymentTransId": "auth-1",
            "method": "card",
            "operation": "Auth"
          },
          "token": null
        }
        """)
        let component = PayabliPayInPaymentFlow(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            operation: .authorize,
            requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration(
                paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 22, currency: "USD"),
                source: "ios-sdk-test",
                idempotencyKey: "idem-auth",
                achValidation: true,
                forceCustomerCreation: true
            )
        )

        let request = try XCTUnwrap(component.requestConfiguration?.request(
            paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(data: PayabliPayInPaymentFlowCardData(
                cardNumber: "4111111111111111",
                expiration: "02/27",
                cardholderName: "Jane Doe",
                cvv: "999",
                billingZip: "12345"
            )))
        ))
        _ = try await component.submitConfigured(request)

        let submittedRequest = try await firstFacadeRequest(from: transport)
        XCTAssertEqual(submittedRequest.path, "/api/v2/MoneyIn/authorize")
        XCTAssertEqual(submittedRequest.query.map(\.name), ["forceCustomerCreation"])
        XCTAssertEqual(submittedRequest.query.map(\.value), ["true"])
        XCTAssertEqual(submittedRequest.headers["idempotencyKey"], "idem-auth")

        let body = try parseFacadeBody(submittedRequest)
        XCTAssertEqual(body["source"] as? String, "ios-sdk-test")
        let paymentDetails = try XCTUnwrap(body["paymentDetails"] as? [String: Any])
        XCTAssertEqual(paymentDetails["totalAmount"] as? Double, 22)
    }

    func testAuthorizeFormLimitsAvailableMethodsToCardData() {
        let component = PayabliPayInPaymentFlow(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox,
            operation: .authorize,
            requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration(
                paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 10)
            )
        )
        let configuration = PayabliPayInPaymentFlowFormConfiguration(
            allowedMethods: [.ach],
            defaultMethod: .ach
        )

        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: component,
            configuration: configuration
        )

        XCTAssertEqual(viewModel.availableMethods, [.card])
        XCTAssertEqual(viewModel.effectiveSelectedMethod, .card)
        XCTAssertTrue(viewModel.activeFields.contains(.cardNumber))
        XCTAssertFalse(viewModel.activeFields.contains(.achAccount))
    }

    func testViewModelUpdateReconcilesChangedComponentOperationAndConfiguration() {
        let component = PayabliPayInPaymentFlow(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox,
            operation: .storePaymentMethod
        )
        let storeConfiguration = PayabliPayInPaymentFlowFormConfiguration(
            allowedMethods: [.ach],
            defaultMethod: .ach
        )
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: component,
            configuration: storeConfiguration
        )

        XCTAssertEqual(viewModel.effectiveSelectedMethod, .ach)
        XCTAssertFalse(viewModel.activeFields.contains(.amount))

        component.configure(
            operation: .capture,
            requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration(
                paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 15, serviceFee: 0.75)
            )
        )
        let captureConfiguration = PayabliPayInPaymentFlowFormConfiguration(
            allowedMethods: [.card],
            defaultMethod: .card,
            requiredFields: [.billingEmail]
        )

        viewModel.update(
            component: component,
            configuration: captureConfiguration
        )

        XCTAssertEqual(viewModel.availableMethods, [.card])
        XCTAssertEqual(viewModel.effectiveSelectedMethod, .card)
        XCTAssertTrue(viewModel.activeFields.contains(.amount))
        XCTAssertTrue(viewModel.activeFields.contains(.billingEmail))
    }

    func testFacadeRejectsConcurrentSubmissionsBeforeSecondTransportCall() async throws {
        let transport = BlockingFacadeTransport(responseBody: Self.formCaptureResponse)
        let component = PayabliPayInPaymentFlow(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport
        )
        let request = PayabliPayInPaymentFlowRequest(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 10),
            paymentMethod: .cash
        )

        let firstSubmission = Task {
            try await component.capture(request)
        }
        await transport.waitForFirstRequest()
        XCTAssertTrue(component.isSubmitting)

        do {
            _ = try await component.capture(request)
            XCTFail("Expected concurrent submission to be rejected")
        } catch let error as PayabliPayInPaymentFlowError {
            XCTAssertEqual(error, .submissionInProgress)
        }

        await transport.resume()
        _ = try await firstSubmission.value

        XCTAssertFalse(component.isSubmitting)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testFormViewModelSubmitsConfiguredCaptureRequest() async throws {
        let transport = FacadeTransport(responseBody: Self.formCaptureResponse)
        let component = PayabliPayInPaymentFlow(
            accessToken: "access-token",
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            operation: .capture,
            requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration(
                paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 30, serviceFee: 1, currency: "USD"),
                source: "ios-form-test",
                idempotencyKey: "idem-form",
                achValidation: true,
                forceCustomerCreation: false
            )
        )
        let configuration = PayabliPayInPaymentFlowFormConfiguration(
            allowedMethods: [.card],
            defaultMethod: .card,
            hiddenValues: PayabliPayInPaymentFlowHiddenValues(methodDescription: "Configured description")
        )
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: component,
            configuration: configuration
        )
        viewModel.cardholderName = "Jane Doe"
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/27"
        viewModel.cardCvv = "999"
        viewModel.cardZip = "12345"
        viewModel.firstName = "Jane"
        viewModel.billingEmail = "jane@example.com"

        XCTAssertTrue(viewModel.canSubmit)
        let result = try await viewModel.submit()

        XCTAssertEqual(result.transaction?.paymentTransId, "capture-1")
        let submittedRequest = try await firstFacadeRequest(from: transport)
        XCTAssertEqual(submittedRequest.path, "/api/v2/MoneyIn/getpaid")
        XCTAssertEqual(submittedRequest.query.map(\.name), ["achValidation", "forceCustomerCreation"])
        XCTAssertEqual(submittedRequest.query.map(\.value), ["true", "false"])
        XCTAssertEqual(submittedRequest.headers["idempotencyKey"], "idem-form")

        let body = try parseFacadeBody(submittedRequest)
        XCTAssertEqual(body["entryPoint"] as? String, "entry")
        XCTAssertEqual(body["source"] as? String, "ios-form-test")
        XCTAssertEqual(body["orderDescription"] as? String, "Configured description")

        let paymentDetails = try XCTUnwrap(body["paymentDetails"] as? [String: Any])
        XCTAssertEqual(paymentDetails["totalAmount"] as? Double, 30)
        XCTAssertEqual(paymentDetails["serviceFee"] as? Double, 1)
        XCTAssertEqual(paymentDetails["currency"] as? String, "USD")

        let customer = try XCTUnwrap(body["customerData"] as? [String: Any])
        XCTAssertEqual(customer["firstName"] as? String, "Jane")
        XCTAssertEqual(customer["billingEmail"] as? String, "jane@example.com")

        let paymentMethod = try XCTUnwrap(body["paymentMethod"] as? [String: Any])
        XCTAssertEqual(paymentMethod["method"] as? String, "card")
        XCTAssertEqual(paymentMethod["cardnumber"] as? String, "4111111111111111")
    }

    func testPaymentSummaryTextDefaultsAndOverrides() {
        let paymentDetails = PayabliPayInPaymentFlowPaymentDetails(
            totalAmount: 1,
            serviceFee: 0.10,
            currency: "USD"
        )
        let labels = PayabliPayInPaymentFlowLabels()
        let defaultSummary = PayabliPayInPaymentFlowPaymentSummaryConfiguration()

        XCTAssertEqual(
            defaultSummary.labelText(for: .amount, labels: labels),
            "Amount:"
        )
        XCTAssertEqual(
            defaultSummary.valueText(for: .amount, paymentDetails: paymentDetails),
            "$ 1.00"
        )
        XCTAssertEqual(
            defaultSummary.labelText(for: .serviceFee, labels: labels),
            "Fee:"
        )
        XCTAssertEqual(
            defaultSummary.valueText(for: .serviceFee, paymentDetails: paymentDetails),
            "$ 0.10"
        )
        XCTAssertEqual(
            defaultSummary.accessibilityText(for: .amount, labels: labels, paymentDetails: paymentDetails),
            "Amount: $ 1.00"
        )

        let customSummary = PayabliPayInPaymentFlowPaymentSummaryConfiguration(
            amountLabelText: "Today:",
            amountValueText: "USD 1.00",
            feeLabelText: "Processing:",
            feeValueText: "USD 0.10",
            rowSpacing: 4
        )
        XCTAssertEqual(
            customSummary.labelText(for: .amount, labels: labels),
            "Today:"
        )
        XCTAssertEqual(
            customSummary.valueText(for: .amount, paymentDetails: paymentDetails),
            "USD 1.00"
        )
        XCTAssertEqual(
            customSummary.labelText(for: .serviceFee, labels: labels),
            "Processing:"
        )
        XCTAssertEqual(
            customSummary.valueText(for: .serviceFee, paymentDetails: paymentDetails),
            "USD 0.10"
        )
        XCTAssertEqual(customSummary.rowSpacing, 4)
    }

    func testFieldSectionsCanConfigurePerSectionTitleStyle() {
        let configuration = PayabliPayInPaymentFlowFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInPaymentFlowFieldSection(
                    title: "Payment Information",
                    titleStyle: PayabliPayInPaymentFlowTextStyle(
                        font: .headline,
                        color: .green
                    ),
                    fields: [.amount, .serviceFee]
                )
            ]
        )

        XCTAssertEqual(configuration.cardSections[0].title, "Payment Information")
        XCTAssertNotNil(configuration.cardSections[0].titleStyle)
        XCTAssertEqual(configuration.cardSections[0].fields, [
            .amount,
            .serviceFee,
            .cardNumber,
            .cardExpiration,
            .cardholderName,
            .cardCvv,
            .cardZip
        ])
    }

    private static let formCaptureResponse = """
    {
      "code": "A0000",
      "reason": "Approved",
      "explanation": "Approved.",
      "action": "No action required.",
      "data": {
        "paymentTransId": "capture-1",
        "method": "card",
        "operation": "Sale"
      },
      "token": null
    }
    """
}

private actor FacadeTransport: PayabliTransport {
    private(set) var requests: [PayabliRequest] = []
    private let responseBody: String

    init(responseBody: String) {
        self.responseBody = responseBody
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        requests.append(request)
        return PayabliResponse(
            statusCode: 201,
            headers: [:],
            body: Data(responseBody.utf8)
        )
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        requests.append(request)
        return try JSONDecoder().decode(PayabliV2Envelope<T>.self, from: Data(responseBody.utf8))
    }
}

private actor BlockingFacadeTransport: PayabliTransport {
    private(set) var requests: [PayabliRequest] = []
    private let responseBody: String
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private var responseContinuation: CheckedContinuation<Void, Never>?

    init(responseBody: String) {
        self.responseBody = responseBody
    }

    func waitForFirstRequest() async {
        guard requests.isEmpty else { return }
        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func resume() {
        responseContinuation?.resume()
        responseContinuation = nil
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        requests.append(request)
        requestContinuation?.resume()
        requestContinuation = nil

        await withCheckedContinuation { continuation in
            responseContinuation = continuation
        }
        return PayabliResponse(
            statusCode: 201,
            headers: [:],
            body: Data(responseBody.utf8)
        )
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        requests.append(request)
        return try JSONDecoder().decode(PayabliV2Envelope<T>.self, from: Data(responseBody.utf8))
    }
}

private func firstFacadeRequest(from transport: FacadeTransport) async throws -> PayabliRequest {
    let requests = await transport.requests
    return try XCTUnwrap(requests.first)
}

private func parseFacadeBody(_ request: PayabliRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.body)
    let object = try JSONSerialization.jsonObject(with: body)
    return try XCTUnwrap(object as? [String: Any])
}
