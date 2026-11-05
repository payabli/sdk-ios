import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A digit is ASCII `0` to `9` in every instrument field. One from another script, here a fullwidth `１`, is
/// refused before sending, and the form never holds one, so it never reads complete on a value it can't send. The
/// same holds for an ASCII digit carrying a combining mark, such as `1` with an accent or a keycap `1️⃣`.
@MainActor
final class PayInDigitRuleTests: XCTestCase {
    private static let fullwidthOne = "\u{FF11}"
    private static let accentedOne = "1\u{301}"
    private static let keycapOne = "1\u{FE0F}\u{20E3}"

    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    override func tearDown() {
        PayInKeyStore.process.forgetHeld()
        super.tearDown()
    }

    // MARK: - Refused before sending

    func testACardNumberWithAFullwidthDigitIsRefusedUnsent() async {
        await assertRefusedUnsent(.card(Self.card(number: "411111111111111" + Self.fullwidthOne)))
    }

    func testASecurityCodeWithAFullwidthDigitIsRefusedUnsent() async {
        await assertRefusedUnsent(.card(Self.card(securityCode: "99" + Self.fullwidthOne)))
    }

    func testAnAccountNumberWithAFullwidthDigitIsRefusedUnsent() async {
        await assertRefusedUnsent(.bankAccount(Self.bank(account: "12345678901" + Self.fullwidthOne)))
    }

    func testARoutingNumberWithAFullwidthDigitIsRefusedUnsent() async {
        await assertRefusedUnsent(.bankAccount(Self.bank(routing: "02100002" + Self.fullwidthOne)))
    }

    // MARK: - The form holds none

    func testTheFormsCardNumberHoldsNoFullwidthDigit() {
        let viewModel = Self.form()
        viewModel.cardNumber = "411111111111111" + Self.fullwidthOne
        XCTAssertEqual(viewModel.cardNumber.filter { !$0.isASCII }, "", "the field kept a digit it can't send")
    }

    func testTheFormsSecurityCodeIsNotCompleteOnAFullwidthDigit() {
        let viewModel = Self.form()
        viewModel.cardCvv = "99" + Self.fullwidthOne
        XCTAssertFalse(viewModel.fieldHasRequiredValue(.cardSecurityCode), "two digits and a fullwidth one read as a code")
    }

    func testTheFormsExpiryIsNotCompleteOnAFullwidthDigit() {
        let viewModel = Self.form()
        viewModel.cardExpiration = "0" + Self.fullwidthOne + "/30"
        XCTAssertFalse(viewModel.fieldHasRequiredValue(.cardExpiration), "three digits and a fullwidth one read as an expiry")
    }

    func testTheFormsAccountNumberHoldsNoFullwidthDigit() {
        let viewModel = Self.form()
        viewModel.accountNumber = "12345678901" + Self.fullwidthOne
        XCTAssertEqual(viewModel.accountNumber.filter { !$0.isASCII }, "", "the field kept a digit it can't send")
    }

    func testTheFormsRoutingNumberIsNotCompleteOnAFullwidthDigit() {
        let viewModel = Self.form()
        viewModel.routingNumber = "02100002" + Self.fullwidthOne
        XCTAssertFalse(viewModel.fieldHasRequiredValue(.routingNumber), "eight digits and a fullwidth one read as nine")
    }

    // MARK: - A digit with a combining mark

    func testACardNumberWithAnAccentedDigitIsRefusedUnsent() async {
        await assertRefusedUnsent(.card(Self.card(number: "411111111111111" + Self.accentedOne)))
    }

    func testARoutingNumberWithAKeycapDigitIsRefusedUnsent() async {
        await assertRefusedUnsent(.bankAccount(Self.bank(routing: "02100002" + Self.keycapOne)))
    }

    func testTheFormsCardNumberHoldsNoAccentedOrKeycapDigit() {
        let viewModel = Self.form()
        viewModel.cardNumber = "41111111111111" + Self.accentedOne + Self.keycapOne
        XCTAssertEqual(viewModel.cardNumber.filter { !$0.isASCII }, "", "the field kept a digit it can't send")
    }

    func testTheFormsSecurityCodeIsNotCompleteOnAnAccentedDigit() {
        let viewModel = Self.form()
        viewModel.cardCvv = "99" + Self.accentedOne
        XCTAssertFalse(viewModel.fieldHasRequiredValue(.cardSecurityCode), "two digits and an accented one read as a code")
    }

    func testTheFormsExpiryIsNotCompleteOnAKeycapDigit() {
        let viewModel = Self.form()
        viewModel.cardExpiration = "0" + Self.keycapOne + "/30"
        XCTAssertFalse(viewModel.fieldHasRequiredValue(.cardExpiration), "three digits and a keycap one read as an expiry")
    }

    func testTheFormsRoutingNumberIsNotCompleteOnAnAccentedDigit() {
        let viewModel = Self.form()
        viewModel.routingNumber = "02100002" + Self.accentedOne
        XCTAssertFalse(viewModel.fieldHasRequiredValue(.routingNumber), "eight digits and an accented one read as nine")
    }

    // MARK: - Fixtures

    private func assertRefusedUnsent(
        _ method: PayabliPayInPaymentMethod,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let request = PayabliPayInRequest(
            paymentMethod: method,
            options: PayabliPayInRequestConfiguration(paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10))
        )

        let refusal = await PayInFixture.failure(from: { _ = try await flow.capture(request) }, file: file, line: line)

        XCTAssertEqual(transport.count, 0, "the value reached the service", file: file, line: line)
        XCTAssertTrue(
            "\(String(describing: refusal))".contains("contains unsupported characters"),
            "refused for another reason: \(String(describing: refusal))",
            file: file,
            line: line
        )
    }

    private static func card(
        number: String = "4111111111111111",
        securityCode: String = "999"
    ) -> PayabliPayInPaymentMethod.Card {
        PayabliPayInPaymentMethod.Card(data: PayabliPayInCardData(
            cardNumber: number,
            expiryMonth: 2,
            expiryYear: 2030,
            securityCode: securityCode,
            holderName: "Jane Doe",
            postalCode: "12345"
        ))
    }

    private static func bank(
        account: String = "123456789012",
        routing: String = "021000021"
    ) -> PayabliPayInPaymentMethod.BankAccount {
        PayabliPayInPaymentMethod.BankAccount(data: PayabliPayInBankAccountData(
            accountNumber: account,
            routingNumber: routing,
            accountType: .checking,
            holderName: "Jane Doe"
        ))
    }

    private static func form() -> PayabliPayInViewModel {
        PayabliPayInViewModel(
            component: PayInFixture.makeFlow(
                transport: RecordingIdempotencyTransport(body: PayInFixture.approved),
                key: "k1"
            ),
            operation: .storePaymentMethod(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card, .bankAccount])
        )
    }
}
