import Foundation
import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

final class PaymentMethodRejectedFieldsTests: XCTestCase {
    // MARK: - What the caller catches

    @MainActor
    func testAFieldKeyedRefusalReachesTheCallerAsAValidationErrorCarryingTheFields() async throws {
        let transport = MockPaymentCaptureTransport(
            statusCode: 400,
            responseBody: Self.refusal(naming: ["paymentMethod.cardnumber", "customerData.firstName"])
        )
        let viewModel = filledCardForm(transport: transport)

        do {
            _ = try await viewModel.submit()
            XCTFail("a refusal must not read as a payment")
        } catch let PayabliPaymentError.validation(refusal) {
            XCTAssertEqual(Set(refusal.errors?.keys.map { $0 } ?? []), ["paymentMethod.cardnumber", "customerData.firstName"])
            XCTAssertEqual(refusal.rawCode, "E7002")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    /// Only a 400 is read as a field-keyed refusal. A failure on any other status keeps its own shape.
    @MainActor
    func testADeclineOnAServerStatusStillArrivesAsATransactionFailure() async throws {
        let transport = MockPaymentCaptureTransport(statusCode: 500, responseBody: Self.decline)
        let viewModel = filledCardForm(transport: transport)

        do {
            _ = try await viewModel.submit()
            XCTFail("a decline must not read as a payment")
        } catch let PayabliPayInPaymentFlowError.transactionFailed(failure) {
            XCTAssertEqual(failure.code, "D0200")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
        XCTAssertEqual(viewModel.rejectedFields, [])
    }

    // MARK: - What the form marks

    @MainActor
    func testTheFormMarksEachFieldTheRefusalNamedWhateverItsCaseOrParent() async {
        let viewModel = filledCardForm(
            transport: MockPaymentCaptureTransport(
                statusCode: 400,
                responseBody: Self.refusal(naming: ["paymentMethod.cardnumber", "PaymentMethod.CardHolder"])
            )
        )

        _ = try? await viewModel.submit()

        XCTAssertEqual(viewModel.rejectedFields, [.cardNumber, .cardholderName])
    }

    @MainActor
    func testANameWithNoBoxOnScreenMarksNothing() async {
        let viewModel = filledCardForm(
            transport: MockPaymentCaptureTransport(
                statusCode: 400,
                responseBody: Self.refusal(naming: ["entryPoint", "paymentMethod.achRouting", "paymentDetails.totalAmount"])
            )
        )

        _ = try? await viewModel.submit()

        XCTAssertEqual(viewModel.rejectedFields, [])
    }

    @MainActor
    func testEditingAMarkedFieldClearsOnlyItsOwnMark() async {
        let viewModel = filledCardForm(
            transport: MockPaymentCaptureTransport(
                statusCode: 400,
                responseBody: Self.refusal(naming: ["paymentMethod.cardHolder", "paymentMethod.cardzip"])
            )
        )
        _ = try? await viewModel.submit()
        XCTAssertEqual(viewModel.rejectedFields, [.cardholderName, .cardZip])

        viewModel.cardholderName = "Janet Doe"

        XCTAssertEqual(viewModel.rejectedFields, [.cardZip])
    }

    @MainActor
    func testTheFormCannotResendAValueTheServiceRefused() async {
        let viewModel = filledCardForm(
            transport: MockPaymentCaptureTransport(
                statusCode: 400,
                responseBody: Self.refusal(naming: ["paymentMethod.cardHolder"])
            )
        )
        _ = try? await viewModel.submit()
        fillCard(viewModel)
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.cardholderName = "Janet Doe"

        XCTAssertTrue(viewModel.canSubmit)
    }

    @MainActor
    func testSwitchingMethodKeepsAMarkOnlyWhereTheNewMethodHasTheBox() async {
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: captureFlow(
                transport: MockPaymentCaptureTransport(
                    statusCode: 400,
                    responseBody: Self.refusal(naming: ["paymentMethod.cardnumber", "customerData.firstName"])
                )
            ),
            configuration: PayabliPayInPaymentFlowFormConfiguration(
                allowedMethods: [.card, .bankAccount],
                cardFieldOrder: PayabliPayInPaymentFlowFormConfiguration.defaultCardFieldOrder + [.firstName],
                achFieldOrder: PayabliPayInPaymentFlowFormConfiguration.defaultACHFieldOrder + [.firstName]
            )
        )
        fillCard(viewModel)
        viewModel.firstName = "Jane"
        _ = try? await viewModel.submit()
        XCTAssertEqual(viewModel.rejectedFields, [.cardNumber, .firstName])

        viewModel.selectedMethod = .bankAccount

        XCTAssertEqual(viewModel.rejectedFields, [.firstName])
    }

    /// The pre-fill that opens the wheel is not a pick, so it leaves the mark standing until the payer
    /// chooses a date.
    @MainActor
    func testOpeningTheExpiryPickerDoesNotClearItsMark() async {
        let viewModel = filledCardForm(
            transport: MockPaymentCaptureTransport(
                statusCode: 400,
                responseBody: Self.refusal(naming: ["paymentMethod.cardexp"])
            )
        )
        _ = try? await viewModel.submit()
        XCTAssertEqual(viewModel.rejectedFields, [.cardExpiration])

        viewModel.ensureExpirationSelection(defaultDate: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(viewModel.rejectedFields, [.cardExpiration])

        viewModel.selectExpirationMonth(3)

        XCTAssertEqual(viewModel.rejectedFields, [])
    }

    @MainActor
    func testAFailureThatNamesNoFieldMarksNothingAndClearsTheLastMarks() async {
        let transport = SequencedCaptureTransport(responses: [
            (400, Self.refusal(naming: ["paymentMethod.cardHolder"])),
            (402, Self.decline)
        ])
        let viewModel = filledCardForm(transport: transport)
        _ = try? await viewModel.submit()
        XCTAssertEqual(viewModel.rejectedFields, [.cardholderName])

        fillCard(viewModel)
        _ = try? await viewModel.submit()

        XCTAssertEqual(viewModel.rejectedFields, [])
    }

    @MainActor
    func testASubmissionThatSucceedsLeavesNoMarkBehind() async throws {
        let transport = SequencedCaptureTransport(responses: [
            (400, Self.refusal(naming: ["paymentMethod.cardHolder"])),
            (201, Self.approval)
        ])
        let viewModel = filledCardForm(transport: transport)
        _ = try? await viewModel.submit()
        XCTAssertEqual(viewModel.rejectedFields, [.cardholderName])

        fillCard(viewModel)
        _ = try await viewModel.submit()

        XCTAssertEqual(viewModel.rejectedFields, [])
    }

    @MainActor
    func testATransportFailureMarksNothing() async {
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: PayabliPayInPaymentFlow(
                entryPoint: "entry",
                environment: .sandbox,
                transport: UnreachableTransport(),
                operation: .capture,
                requestConfiguration: Self.requestConfiguration
            ),
            configuration: PayabliPayInPaymentFlowFormConfiguration(allowedMethods: [.card])
        )
        fillCard(viewModel)

        _ = try? await viewModel.submit()

        XCTAssertEqual(viewModel.rejectedFields, [])
    }

    /// A store failure keeps its own shape, so a refusal there marks nothing.
    @MainActor
    func testAStoreRefusalKeepsItsOwnShapeAndMarksNothing() async {
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: PayabliPayInPaymentFlow(
                entryPoint: "entry",
                environment: .sandbox,
                transport: MockPaymentCaptureTransport(
                    statusCode: 400,
                    responseBody: #"{"isSuccess":false,"responseText":"Invalid card number"}"#
                )
            ),
            configuration: PayabliPayInPaymentFlowFormConfiguration(allowedMethods: [.card])
        )
        fillCard(viewModel)

        do {
            _ = try await viewModel.submit()
            XCTFail("a refusal must not read as a stored method")
        } catch PayabliPayInPaymentFlowTokenStorageError.saveFailed {
        } catch {
            XCTFail("Wrong error: \(error)")
        }
        XCTAssertEqual(viewModel.rejectedFields, [])
    }

    // MARK: - The table against the encoder

    /// Every name the table resolves is one this SDK actually sends, so a renamed key cannot leave a mark
    /// that never lands.
    @MainActor
    func testEveryNameTheTableResolvesIsOneTheRequestCarries() async throws {
        let cardTransport = MockPaymentCaptureTransport(responseBody: Self.approval)
        let cardForm = filledCardForm(transport: cardTransport, customerFields: true)
        _ = try await cardForm.submit()

        let achTransport = MockPaymentCaptureTransport(responseBody: Self.approval)
        let achForm = PayabliPayInPaymentFlowViewModel(
            component: captureFlow(transport: achTransport),
            configuration: PayabliPayInPaymentFlowFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount,
                achFieldOrder: PayabliPayInPaymentFlowFormConfiguration.defaultACHFieldOrder + [.achSecCode, .achDevice]
            )
        )
        achForm.achHolder = "Jane Doe"
        achForm.achRouting = "021000021"
        achForm.achAccount = "123456789"
        achForm.achDevice = "device-1"
        _ = try await achForm.submit()

        var sent: Set<String> = []
        for transport in [cardTransport, achTransport] {
            for request in await transport.requests {
                let body = try XCTUnwrap(request.body)
                sent.formUnion(Self.keys(in: try JSONSerialization.jsonObject(with: body)))
            }
        }

        let unsent = Set(PayabliPayInPaymentFlowRejectedFields.fieldsByWireName.keys).subtracting(sent)
        XCTAssertEqual(unsent, [], "the table resolves names the request never carries")
    }

    // MARK: - Fixtures

    private static let requestConfiguration = PayabliPayInPaymentFlowRequestConfiguration(
        paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 15)
    )

    @MainActor
    private func captureFlow(transport: any PayabliTransport) -> PayabliPayInPaymentFlow {
        PayabliPayInPaymentFlow(
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            operation: .capture,
            requestConfiguration: Self.requestConfiguration
        )
    }

    @MainActor
    private func filledCardForm(
        transport: any PayabliTransport,
        customerFields: Bool = false
    ) -> PayabliPayInPaymentFlowViewModel {
        let customer: [PayabliPayInPaymentFlowField] = [.firstName, .lastName, .customerNumber, .billingEmail, .billingZip]
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: captureFlow(transport: transport),
            configuration: PayabliPayInPaymentFlowFormConfiguration(
                allowedMethods: [.card],
                cardFieldOrder: PayabliPayInPaymentFlowFormConfiguration.defaultCardFieldOrder
                    + (customerFields ? customer : [])
            )
        )
        fillCard(viewModel)
        if customerFields {
            viewModel.firstName = "Jane"
            viewModel.lastName = "Doe"
            viewModel.customerNumber = "C-1"
            viewModel.billingEmail = "jane@example.com"
            viewModel.billingZip = "33139"
        }
        return viewModel
    }

    /// The instrument is cleared after a failure, so a resubmission types it again.
    @MainActor
    private func fillCard(_ viewModel: PayabliPayInPaymentFlowViewModel) {
        if viewModel.cardholderName.isEmpty {
            viewModel.cardholderName = "Jane Doe"
        }
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "02/30"
        viewModel.cardCvv = "123"
        if viewModel.cardZip.isEmpty {
            viewModel.cardZip = "33139"
        }
    }

    private static func keys(in object: Any) -> Set<String> {
        if let dictionary = object as? [String: Any] {
            return dictionary.reduce(into: Set(dictionary.keys.map { $0.lowercased() })) { keys, entry in
                keys.formUnion(Self.keys(in: entry.value))
            }
        }
        if let array = object as? [Any] {
            return array.reduce(into: Set<String>()) { $0.formUnion(Self.keys(in: $1)) }
        }
        return []
    }

    /// A validation refusal keyed by the parameters at fault.
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

    private static let decline = """
    {
      "code": "D0200",
      "reason": "Insufficient Funds",
      "explanation": "The card issuer declined the transaction.",
      "action": "Ask for a different payment method.",
      "data": null,
      "token": null
    }
    """

    private static let approval = """
    {
      "code": "A0000",
      "reason": "Approved",
      "explanation": "Transaction approved",
      "action": "No action required.",
      "data": {
        "paymentTransId": "3040-1",
        "method": "card",
        "transStatus": 1
      },
      "token": null
    }
    """
}

/// Answers each call with the next response, so one test can drive two submissions to two outcomes.
private actor SequencedCaptureTransport: PayabliTransport {
    private var responses: [(Int, String)]

    init(responses: [(Int, String)]) {
        self.responses = responses
    }

    func perform(_: PayabliRequest) async throws -> PayabliResponse {
        let (statusCode, body) = responses.removeFirst()
        return PayabliResponse(statusCode: statusCode, headers: [:], body: Data(body.utf8))
    }

    func performV2<T: Decodable & Sendable>(
        _: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw URLError(.notConnectedToInternet)
    }
}

/// Fails every call the way a dropped connection does.
private struct UnreachableTransport: PayabliTransport {
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
