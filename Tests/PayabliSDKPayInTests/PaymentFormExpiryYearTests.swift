@testable import PayabliSDKPayIn
import XCTest

/// The form's expiry picker reads the current month on the Gregorian calendar, with the year held to 2000 to 2099,
/// and offers that year and the 20 after it, up to 2099.
@MainActor
final class PaymentFormExpiryYearTests: XCTestCase {
    func testThePickerStartsAtThisGregorianYear() {
        let thisYear = Calendar(identifier: .gregorian).component(.year, from: Date())

        let years = Self.form().expirationYearChoices(now: Date())

        XCTAssertEqual(years.first, thisYear)
        XCTAssertEqual(years.count, 21)
    }

    func testA1970ClockStartsThePickerAt2000() {
        let years = Self.form().expirationYearChoices(now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(years, Array(2000 ... 2020))
    }

    func testA2150ClockOffers2099Only() throws {
        let years = try Self.form().expirationYearChoices(now: Self.date(year: 2150, month: 6))

        XCTAssertEqual(years, [2099])
    }

    func testA2090ClockStopsThePickerAt2099() throws {
        let years = try Self.form().expirationYearChoices(now: Self.date(year: 2090, month: 6))

        XCTAssertEqual(years, Array(2090 ... 2099))
    }

    func testNoYearBefore2000OrAfter2099IsEverOffered() throws {
        for year in [1, 1970, 1999, 2000, 2026, 2099, 2100, 2569, 9999] {
            let years = try Self.form().expirationYearChoices(now: Self.date(year: year, month: 1))
            XCTAssertFalse(years.isEmpty, "\(year)")
            XCTAssertTrue(years.allSatisfy { (2000 ... 2099).contains($0) }, "\(year): \(years)")
        }
    }

    func testTheDefaultSelectionOnA1970ClockIsJanuary2000() throws {
        let viewModel = Self.form()

        try viewModel.ensureExpirationSelection(defaultDate: Self.date(year: 1970, month: 1))

        XCTAssertEqual(viewModel.cardExpirationMonth, 1)
        XCTAssertEqual(viewModel.cardExpirationYear, 2000)
    }

    func testTheDefaultSelectionOnA2150ClockIsIn2099() throws {
        let viewModel = Self.form()

        try viewModel.ensureExpirationSelection(defaultDate: Self.date(year: 2150, month: 6))

        XCTAssertEqual(viewModel.cardExpirationMonth, 6)
        XCTAssertEqual(viewModel.cardExpirationYear, 2099)
    }

    private static func form() -> PayabliPayInViewModel {
        PayabliPayInViewModel(
            component: flowOnSession(token: "access-token", entryPoint: "entry", environment: .sandbox),
            operation: .storePaymentMethod()
        )
    }

    private static func date(year: Int, month: Int) throws -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: 15, hour: 12)))
    }
}
