import XCTest

final class AmountEntryTests: XCTestCase {
    func testTheInitialTextReadsBackAsTheSameAmountInEveryLocale() {
        for identifier in ["en_US", "de_DE", "fr_FR", "pt_BR", "ja_JP"] {
            let locale = Locale(identifier: identifier)
            let text = AmountEntry.text(for: 10, locale: locale)

            XCTAssertEqual(AmountEntry.amount(from: text, locale: locale), 10, "\(identifier) read \(text)")
        }
    }
}
