@testable import PayabliSDKPayIn
import XCTest

final class PaymentSummaryAmountTests: XCTestCase {
    private let summary = PayabliPayInPaymentSummaryConfiguration()

    private func details(
        _ totalAmount: Double,
        fee: Double? = nil,
        surcharge: Double? = nil
    ) -> PayabliPayInPaymentDetails {
        PayabliPayInPaymentDetails(totalAmount: totalAmount, serviceFee: fee, surchargeFee: surcharge, currency: "USD")
    }

    private func amount(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }

    // MARK: - Which rows have a figure

    func testEachFeeFieldReadsItsOwnFigure() {
        let fee = details(12.34, fee: 0.5)
        let surcharge = details(12.34, surcharge: 0.31)

        XCTAssertEqual(summary.rowAmount(for: .serviceFee, paymentDetails: fee), amount("0.5"))
        XCTAssertEqual(summary.rowAmount(for: .surchargeFee, paymentDetails: surcharge), amount("0.31"))
    }

    func testAnAbsentOrZeroFigureHasNoRow() {
        XCTAssertNil(summary.rowAmount(for: .serviceFee, paymentDetails: details(12.34)))
        XCTAssertNil(summary.rowAmount(for: .serviceFee, paymentDetails: details(12.34, fee: 0)))
        XCTAssertNil(summary.rowAmount(for: .serviceFee, paymentDetails: nil))
        XCTAssertNil(summary.totalRowAmount(paymentDetails: nil))
    }

    func testAFigureSentAsZeroHasNoRow() {
        XCTAssertNil(summary.rowAmount(for: .serviceFee, paymentDetails: details(12.34, fee: 0.001)))
    }

    func testAFigureThatCannotBeSentHasNoRowRatherThanFailing() {
        for unsendable in [Double.infinity, -Double.infinity, .nan, 1e30, .greatestFiniteMagnitude] {
            XCTAssertNil(summary.rowAmount(for: .serviceFee, paymentDetails: details(12.34, fee: unsendable)))
            XCTAssertNil(summary.totalRowAmount(paymentDetails: details(unsendable)))
        }
    }

    func testANegativeFigureThatIsSentHasARow() {
        XCTAssertEqual(
            summary.rowAmount(for: .surchargeFee, paymentDetails: details(12.34, surcharge: -0.31)),
            amount("-0.31")
        )
    }

    func testAFieldThatIsNotAnAmountHasNoFigure() {
        XCTAssertNil(summary.rowAmount(for: .cardNumber, paymentDetails: details(12.34, fee: 0.5)))
    }

    // MARK: - The base and the total

    func testTheAmountIsTheChargeLessTheFeeAndTheTotalAddsTheSurcharge() {
        let fee = details(12.34, fee: 0.5)

        XCTAssertEqual(summary.rowAmount(for: .amount, paymentDetails: fee), amount("11.84"))
        XCTAssertEqual(summary.totalRowAmount(paymentDetails: fee), amount("12.34"))
    }

    func testOnASurchargedChargeTheAmountIsWhatWasSentAndTheTotalAddsTheSurcharge() {
        let surcharged = details(12.34, surcharge: 0.31)

        XCTAssertEqual(summary.rowAmount(for: .amount, paymentDetails: surcharged), amount("12.34"))
        XCTAssertEqual(summary.totalRowAmount(paymentDetails: surcharged), amount("12.65"))
    }

    func testWithNothingTakenOutOfTheChargeOnlyTheTotalHasAFigure() {
        let plain = details(12.34)

        XCTAssertNil(summary.rowAmount(for: .amount, paymentDetails: plain))
        XCTAssertEqual(summary.totalRowAmount(paymentDetails: plain), amount("12.34"))
    }

    func testASurchargeThatCancelsTheChargeLeavesTheAmountAndNoTotal() {
        let cancelled = details(12.34, surcharge: -12.34)

        XCTAssertEqual(summary.rowAmount(for: .amount, paymentDetails: cancelled), amount("12.34"))
        XCTAssertNil(summary.totalRowAmount(paymentDetails: cancelled))
    }

    func testAChargeThatIsAllFeeHasTheFeeAndTheTotalAndNoAmount() {
        let allFee = details(0.5, fee: 0.5)

        XCTAssertNil(summary.rowAmount(for: .amount, paymentDetails: allFee))
        XCTAssertEqual(summary.rowAmount(for: .serviceFee, paymentDetails: allFee), amount("0.5"))
        XCTAssertEqual(summary.totalRowAmount(paymentDetails: allFee), amount("0.5"))
    }

    func testAFigureIsReadAtTheTwoPlacesItIsSent() {
        XCTAssertEqual(summary.totalRowAmount(paymentDetails: details(12.345)), amount("12.35"))
        XCTAssertEqual(summary.totalRowAmount(paymentDetails: details(0.1)), amount("0.1"))
    }

    // MARK: - Formatting

    private func formatted(_ text: String, _ currency: String?, _ locale: String) -> String {
        PayabliPayInPaymentSummaryConfiguration.formattedAmount(
            amount(text),
            currency: currency,
            locale: Locale(identifier: locale)
        )
    }

    func testTheTextIsTheFigureSentAtTwoPlaces() {
        XCTAssertEqual(formatted("12.345", "USD", "en_US"), "$12.35")
        XCTAssertEqual(formatted("1234.5", "USD", "en_US"), "$1,234.50")
    }

    func testTheDeviceLocaleWritesTheSeparatorsAndTheCurrencyGivesTheSymbol() {
        XCTAssertEqual(formatted("1234.56", "EUR", "de_DE"), "1.234,56\u{00A0}€")
        XCTAssertEqual(formatted("1234.56", "EUR", "en_US"), "€1,234.56")
    }

    func testACurrencyWithNoMinorUnitStillShowsTheTwoPlacesSent() {
        XCTAssertEqual(formatted("1234.56", "JPY", "en_US"), "¥1,234.56")
    }

    func testACurrencyTheRequestDoesNotNameWritesTheNumberAlone() {
        XCTAssertEqual(formatted("1234.56", nil, "en_US"), "1,234.56")
        XCTAssertEqual(formatted("1234.56", nil, "de_DE"), "1.234,56")
        XCTAssertEqual(formatted("1234.56", "dollars", "en_US"), "1,234.56")
    }

    func testACodeInLowerCaseOrWithSpacesIsStillTheCurrencyItNames() {
        XCTAssertEqual(formatted("12.34", " usd ", "en_US"), "$12.34")
        XCTAssertEqual(formatted("12.34", "USD\n", "en_US"), "$12.34")
    }

    func testANegativeFigureIsWrittenWithItsSign() {
        XCTAssertEqual(formatted("-0.31", "USD", "en_US"), "-$0.31")
    }
}
