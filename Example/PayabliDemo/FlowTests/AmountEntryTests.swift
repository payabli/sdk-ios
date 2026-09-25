import XCTest

final class AmountEntryTests: XCTestCase {
    func testTheInitialTextReadsBackAsTheSameAmountInEveryLocale() {
        for identifier in ["en_US", "de_DE", "fr_FR", "pt_BR", "ja_JP"] {
            let locale = Locale(identifier: identifier)
            let text = AmountEntry.text(for: 10, locale: locale)

            XCTAssertEqual(AmountEntry.amount(from: text, locale: locale), 10, "\(identifier) read \(text)")
        }
    }

    func testOnlyAPositiveAmountWithAtMostTwoDecimalsIsRead() {
        let german = Locale(identifier: "de_DE")

        XCTAssertEqual(AmountEntry.amount(from: "12,5", locale: german), 12.5)
        XCTAssertEqual(AmountEntry.amount(from: " 7 ", locale: german), 7)
        for text in ["", "0", "0,00", "-1", "12,345", "1.000,00", "12.50", "abc", "12,"] {
            XCTAssertNil(AmountEntry.amount(from: text, locale: german), "\(text) was read")
        }
    }
}
