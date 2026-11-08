@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// The holder type a bank account form sends, and the device ID it never sends.
@MainActor
final class PaymentMethodAccountHolderTypeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    func testAConfiguredHolderTypeIsSentWhenTheFieldIsHidden() async throws {
        let paymentMethod = try await storedBankMethod(
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount,
                bankFieldOrder: Self.fieldsWithoutHolderType,
                accountHolderType: .business
            )
        )

        XCTAssertEqual(paymentMethod["achHolderType"] as? String, "business")
        XCTAssertEqual(paymentMethod["achCode"] as? String, "WEB")
    }

    func testThePayersChoiceIsSentWhenTheFieldIsShown() async throws {
        let paymentMethod = try await storedBankMethod(
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount,
                bankFieldOrder: PayabliPayInFormConfiguration.defaultBankFieldOrder,
                accountHolderType: .business
            ),
            holderType: .personal
        )

        XCTAssertEqual(paymentMethod["achHolderType"] as? String, "personal")
    }

    func testNoHolderTypeIsSentWithNeitherTheFieldNorAConfiguredValue() async throws {
        let paymentMethod = try await storedBankMethod(
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount,
                bankFieldOrder: Self.fieldsWithoutHolderType
            )
        )

        XCTAssertNil(paymentMethod["achHolderType"])
    }

    func testABankPaymentSendsTheConfiguredHolderTypeAndNoDevice() async throws {
        let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.approvedPayment)
        let viewModel = PayabliPayInViewModel(
            component: PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport),
            operation: .capture(PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34)
            )),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount,
                bankFieldOrder: Self.fieldsWithoutHolderType,
                accountHolderType: .business
            )
        )
        fillBankAccount(viewModel)

        _ = try await viewModel.submit()

        let paymentMethod = try await sentPaymentMethod(transport)
        XCTAssertEqual(paymentMethod["achHolderType"] as? String, "business")
        XCTAssertNil(paymentMethod["device"], "a card-not-present payment sent a device ID")
    }

    func testAStoredBankMethodSendsNoDevice() async throws {
        let paymentMethod = try await storedBankMethod(
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.bankAccount], defaultMethod: .bankAccount)
        )

        XCTAssertNil(paymentMethod["device"], "a stored method sent a device ID")
    }

    // MARK: - Helpers

    private static let fieldsWithoutHolderType: [PayabliPayInField] = [
        .accountHolder, .routingNumber, .accountNumber, .accountType
    ]

    private static let approvedPayment = """
    {"code":"A0000","reason":"Approved","responseData":{"authCode":"1","referenceId":"trans-1"}}
    """

    private static let storedMethod = """
    {"responseText":"Success","isSuccess":true,
     "responseData":{"referenceId":"ach-1","resultCode":1,"resultText":"Approved","methodReferenceId":"ach-1"}}
    """

    private func storedBankMethod(
        configuration: PayabliPayInFormConfiguration,
        holderType: PayabliPayInAccountHolderType? = nil
    ) async throws -> [String: Any] {
        let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.storedMethod)
        let viewModel = PayabliPayInViewModel(
            component: PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport),
            operation: .storePaymentMethod(),
            configuration: configuration
        )
        fillBankAccount(viewModel)
        if let holderType {
            viewModel.accountHolderType = holderType
        }

        _ = try await viewModel.submit()

        return try await sentPaymentMethod(transport)
    }

    private func fillBankAccount(_ viewModel: PayabliPayInViewModel) {
        viewModel.accountHolder = "Jane Business"
        viewModel.routingNumber = "123456780"
        viewModel.accountNumber = "1111111111111"
    }

    private func sentPaymentMethod(_ transport: MockPaymentCaptureTransport) async throws -> [String: Any] {
        let request = try await firstRequest(from: transport)
        let body = try XCTUnwrap(request.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try XCTUnwrap(object["paymentMethod"] as? [String: Any])
    }
}
