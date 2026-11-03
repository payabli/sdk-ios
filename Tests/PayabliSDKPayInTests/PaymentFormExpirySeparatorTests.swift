@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// The expiration separator is the form's display choice, and never what the form sends.
final class PaymentFormExpirySeparatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    override func tearDown() {
        PayInKeyStore.process.forgetHeld()
        super.tearDown()
    }

    /// The separator is the form's own display choice, so one outside ASCII still lets the form submit, and the
    /// expiry it sends reads `MM/YY`.
    @MainActor
    func testANonAsciiExpirationSeparatorStillSubmitsAsMonthSlashYear() async throws {
        let viewModel = enDashSeparatedForm()
        viewModel.cardExpiration = viewModel.formatExpiration("0230")
        XCTAssertEqual(viewModel.cardExpiration, "02\u{2013}30")
        XCTAssertTrue(viewModel.fieldHasRequiredValue(.cardExpiration), "the form's own separator read as unsupported")

        let method = await viewModel.withFormBuffers { viewModel.paymentMethod(with: $0) }
        guard case let .card(card) = method else {
            return XCTFail("The card tab builds a card method")
        }
        XCTAssertEqual(card.data.expiry, "02/30")
        XCTAssertEqual(try card.data.normalizedExpiration(), "02/30")

        let input = await viewModel.withFormBuffers { viewModel.methodInput(with: $0) }
        guard case let .card(data) = input else {
            return XCTFail("The card tab builds a card input")
        }
        XCTAssertEqual(data.expiry, "02/30")
    }

    /// Only the separator the form wrote is translated: a digit from another script is still not an expiry.
    @MainActor
    func testANonAsciiExpirationSeparatorDoesNotAdmitAFullwidthDigit() {
        let viewModel = enDashSeparatedForm()
        viewModel.cardExpiration = "0\u{FF12}\u{2013}30"
        XCTAssertFalse(viewModel.fieldHasRequiredValue(.cardExpiration), "a fullwidth digit read as an expiry")
    }

    /// A separator that is a combining mark joins the month's second digit in the text, and is still read as the
    /// separator: the form submits `MM/YY` and reads the month it was given.
    @MainActor
    func testACombiningMarkSeparatorStillSubmitsAndKeepsTheMonth() async {
        let viewModel = form(separator: "\u{301}")
        viewModel.cardExpiration = viewModel.formatExpiration("0230")
        XCTAssertTrue(viewModel.fieldHasRequiredValue(.cardExpiration), "the form's own separator read as unsupported")
        XCTAssertEqual(viewModel.expirationDisplayText, "02/30")

        let method = await viewModel.withFormBuffers { viewModel.paymentMethod(with: $0) }
        guard case let .card(card) = method else {
            return XCTFail("The card tab builds a card method")
        }
        XCTAssertEqual(card.data.expiry, "02/30")
    }

    /// A new separator rewrites the expiry the payer already picked, so the form still submits it.
    @MainActor
    func testChangingTheSeparatorRewritesAPickedExpiry() async {
        let viewModel = enDashSeparatedForm()
        viewModel.selectExpirationMonth(2)
        viewModel.selectExpirationYear(2030)
        XCTAssertEqual(viewModel.cardExpiration, "02\u{2013}30")

        viewModel.update(component: viewModel.component, configuration: configuration(separator: "/"))

        XCTAssertEqual(viewModel.cardExpiration, "02/30")
        await assertSubmits("02/30", from: viewModel)
    }

    /// The old separator is read as the old configuration read it, so a combining mark's month digit survives.
    @MainActor
    func testChangingFromACombiningMarkSeparatorKeepsTheMonth() async {
        let viewModel = form(separator: "\u{301}")
        viewModel.cardExpiration = viewModel.formatExpiration("0230")

        viewModel.update(component: viewModel.component, configuration: configuration(separator: "/"))

        XCTAssertEqual(viewModel.cardExpiration, "02/30")
        await assertSubmits("02/30", from: viewModel)
    }

    /// Two spellings of one separator are equal as strings but not as scalars, and the expiry is read by scalar,
    /// so a change between them rewrites the expiry like any other separator change.
    @MainActor
    func testChangingBetweenTwoSpellingsOfOneSeparatorRewritesTheExpiry() async {
        let viewModel = form(separator: "\u{E9}")
        viewModel.cardExpiration = viewModel.formatExpiration("0230")

        viewModel.update(
            component: viewModel.component,
            configuration: configuration(separator: "e\u{301}", insertsCardNumberSpaces: false)
        )

        XCTAssertEqual(Array(viewModel.cardExpiration.unicodeScalars), Array("02e\u{301}30".unicodeScalars))
        await assertSubmits("02/30", from: viewModel)
    }

    @MainActor
    private func assertSubmits(
        _ expiry: String,
        from viewModel: PayabliPayInViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        XCTAssertTrue(viewModel.fieldHasRequiredValue(.cardExpiration), file: file, line: line)
        let method = await viewModel.withFormBuffers { viewModel.paymentMethod(with: $0) }
        guard case let .card(card) = method else {
            return XCTFail("The card tab builds a card method", file: file, line: line)
        }
        XCTAssertEqual(card.data.expiry, expiry, file: file, line: line)
        let input = await viewModel.withFormBuffers { viewModel.methodInput(with: $0) }
        guard case let .card(data) = input else {
            return XCTFail("The card tab builds a card input", file: file, line: line)
        }
        XCTAssertEqual(data.expiry, expiry, file: file, line: line)
    }

    @MainActor
    private func enDashSeparatedForm() -> PayabliPayInViewModel {
        form(separator: "\u{2013}")
    }

    @MainActor
    private func form(separator: String) -> PayabliPayInViewModel {
        PayabliPayInViewModel(
            component: flowOnSession(token: "access-token", entryPoint: "entry", environment: .sandbox),
            configuration: configuration(separator: separator)
        )
    }

    private func configuration(
        separator: String,
        insertsCardNumberSpaces: Bool = true
    ) -> PayabliPayInFormConfiguration {
        PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            formatting: PayabliPayInFormatting(
                insertsCardNumberSpaces: insertsCardNumberSpaces,
                expirationSeparator: separator
            )
        )
    }
}
