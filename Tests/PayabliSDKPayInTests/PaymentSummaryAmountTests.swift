@testable import PayabliSDKPayIn
import XCTest

final class PaymentSummaryAmountTests: XCTestCase {
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

        XCTAssertEqual(PayabliPayInSummaryRows.rowAmount(for: .serviceFee, paymentDetails: fee), amount("0.5"))
        XCTAssertEqual(PayabliPayInSummaryRows.rowAmount(for: .surchargeFee, paymentDetails: surcharge), amount("0.31"))
    }

    func testAnAbsentOrZeroFigureHasNoRow() {
        XCTAssertNil(PayabliPayInSummaryRows.rowAmount(for: .serviceFee, paymentDetails: details(12.34)))
        XCTAssertNil(PayabliPayInSummaryRows.rowAmount(for: .serviceFee, paymentDetails: details(12.34, fee: 0)))
        XCTAssertNil(PayabliPayInSummaryRows.rowAmount(for: .serviceFee, paymentDetails: nil))
        XCTAssertNil(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: nil))
    }

    func testAFigureSentAsZeroHasNoRow() {
        XCTAssertNil(PayabliPayInSummaryRows.rowAmount(for: .serviceFee, paymentDetails: details(12.34, fee: 0.001)))
    }

    func testAFigureThatCannotBeSentHasNoRowRatherThanFailing() {
        for unsendable in [Double.infinity, -Double.infinity, .nan, 1e30, .greatestFiniteMagnitude] {
            XCTAssertNil(PayabliPayInSummaryRows.rowAmount(for: .serviceFee, paymentDetails: details(12.34, fee: unsendable)))
            XCTAssertNil(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: details(unsendable)))
        }
    }

    // MARK: - A figure that cannot be sent empties every reader

    private let unsendable = 1e40

    func testTheAmountIsEmptyWhenAnotherFigureCannotBeSent() {
        let surcharged = details(12.34, fee: 0.5, surcharge: unsendable)

        XCTAssertNil(PayabliPayInSummaryRows.rowAmount(for: .amount, paymentDetails: surcharged))
    }

    func testTheFeeIsEmptyWhenAnotherFigureCannotBeSent() {
        let surcharged = details(12.34, fee: 0.5, surcharge: unsendable)

        XCTAssertNil(PayabliPayInSummaryRows.rowAmount(for: .serviceFee, paymentDetails: surcharged))
    }

    func testTheSurchargeIsEmptyWhenAnotherFigureCannotBeSent() {
        let charged = details(unsendable, fee: 0.5, surcharge: 0.31)

        XCTAssertNil(PayabliPayInSummaryRows.rowAmount(for: .surchargeFee, paymentDetails: charged))
    }

    func testTheTotalIsEmptyWhenTheSurchargeCannotBeSent() {
        XCTAssertNil(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: details(12.34, surcharge: unsendable)))
    }

    // MARK: - A payment submit refuses empties every reader

    private func assertEveryFigureIsEmpty(
        _ paymentDetails: PayabliPayInPaymentDetails,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for field in [PayabliPayInField.amount, .serviceFee, .surchargeFee] {
            XCTAssertNil(
                PayabliPayInSummaryRows.rowAmount(for: field, paymentDetails: paymentDetails),
                "\(field)",
                file: file,
                line: line
            )
        }
        XCTAssertNil(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: paymentDetails), file: file, line: line)
    }

    func testANegativeServiceFeeEmptiesEveryFigure() {
        assertEveryFigureIsEmpty(details(12.34, fee: -0.5, surcharge: 0.31))
    }

    func testATotalOfZeroOrLessEmptiesEveryFigure() {
        assertEveryFigureIsEmpty(details(-5, fee: 0.5, surcharge: 1))
        assertEveryFigureIsEmpty(details(0, fee: 0.5, surcharge: 1))
    }

    func testATotalSentAsZeroEmptiesEveryFigure() {
        assertEveryFigureIsEmpty(details(0.001, fee: 0.5, surcharge: 0.31))
    }

    func testANegativeFigureThatIsSentHasARow() {
        XCTAssertEqual(
            PayabliPayInSummaryRows.rowAmount(for: .surchargeFee, paymentDetails: details(12.34, surcharge: -0.31)),
            amount("-0.31")
        )
    }

    func testAFieldThatIsNotAnAmountHasNoFigure() {
        XCTAssertNil(PayabliPayInSummaryRows.rowAmount(for: .cardNumber, paymentDetails: details(12.34, fee: 0.5)))
    }

    // MARK: - The base and the total

    func testTheAmountIsTheChargeLessTheFeeAndTheTotalAddsTheSurcharge() {
        let fee = details(12.34, fee: 0.5)

        XCTAssertEqual(PayabliPayInSummaryRows.rowAmount(for: .amount, paymentDetails: fee), amount("11.84"))
        XCTAssertEqual(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: fee), amount("12.34"))
    }

    func testOnASurchargedChargeTheAmountIsWhatWasSentAndTheTotalAddsTheSurcharge() {
        let surcharged = details(12.34, surcharge: 0.31)

        XCTAssertEqual(PayabliPayInSummaryRows.rowAmount(for: .amount, paymentDetails: surcharged), amount("12.34"))
        XCTAssertEqual(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: surcharged), amount("12.65"))
    }

    func testWithNothingTakenOutOfTheChargeOnlyTheTotalHasAFigure() {
        let plain = details(12.34)

        XCTAssertNil(PayabliPayInSummaryRows.rowAmount(for: .amount, paymentDetails: plain))
        XCTAssertEqual(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: plain), amount("12.34"))
    }

    func testASurchargeThatCancelsTheChargeLeavesTheAmountAndNoTotal() {
        let cancelled = details(12.34, surcharge: -12.34)

        XCTAssertEqual(PayabliPayInSummaryRows.rowAmount(for: .amount, paymentDetails: cancelled), amount("12.34"))
        XCTAssertNil(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: cancelled))
    }

    func testAChargeSentAsZeroHasNoTotalEvenBesideASurcharge() {
        XCTAssertNil(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: details(0.001, surcharge: 0.5)))
    }

    func testAChargeThatIsAllFeeHasTheFeeAndTheTotalAndNoAmount() {
        let allFee = details(0.5, fee: 0.5)

        XCTAssertNil(PayabliPayInSummaryRows.rowAmount(for: .amount, paymentDetails: allFee))
        XCTAssertEqual(PayabliPayInSummaryRows.rowAmount(for: .serviceFee, paymentDetails: allFee), amount("0.5"))
        XCTAssertEqual(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: allFee), amount("0.5"))
    }

    func testAFigureIsReadAtTheTwoPlacesItIsSent() {
        XCTAssertEqual(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: details(12.345)), amount("12.35"))
        XCTAssertEqual(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: details(0.1)), amount("0.1"))
    }

    // MARK: - Formatting

    private func formatted(_ text: String, _ currency: String?, _ locale: String) -> String {
        PayabliPayInSummaryRows.formattedAmount(
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
