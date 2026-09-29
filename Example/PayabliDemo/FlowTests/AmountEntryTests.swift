import XCTest

final class AmountEntryTests: XCTestCase {
    func testTheInitialTextReadsBackAsTheSameAmountInEveryLocale() {
        for identifier in ["en_US", "de_DE", "fr_FR", "pt_BR", "ja_JP", "ar_EG", "fa_IR"] {
            let locale = Locale(identifier: identifier)
            let text = AmountEntry.text(for: 10, locale: locale)

            XCTAssertEqual(AmountEntry.amount(from: text, locale: locale), 10, "\(identifier) read \(text)")
        }
    }

    func testOnlyAPositiveAmountWithAtMostTwoDecimalsIsRead() {
        let german = Locale(identifier: "de_DE")

        XCTAssertEqual(AmountEntry.amount(from: "12,5", locale: german), 12.5)
        XCTAssertEqual(AmountEntry.amount(from: " 7 ", locale: german), 7)
        XCTAssertEqual(AmountEntry.amount(from: "١٢٫٥", locale: Locale(identifier: "ar_EG")), 12.5)
        for text in ["", "0", "0,00", "-1", "+1", "12,345", "1.000,00", "12.50", "1e3", "abc", "12,", "1 2"] {
            XCTAssertNil(AmountEntry.amount(from: text, locale: german), "\(text) was read")
        }
        XCTAssertNil(
            AmountEntry.amount(from: String(repeating: "9", count: 400), locale: german),
            "an amount too large for a Double was read as infinity"
        )
    }
}
