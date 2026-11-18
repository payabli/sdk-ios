import PayabliSDKCore
import XCTest

final class PayabliCurrencyTests: XCTestCase {
    func testUSDIsSentAsItsISOCode() {
        XCTAssertEqual(PayabliCurrency.usd.code, "USD")
    }

    func testRawValuesArePinnedForObjectiveC() {
        XCTAssertEqual(PayabliCurrency.allCases.map(\.rawValue), [0])
        XCTAssertEqual(PayabliCurrency(rawValue: 0), .usd)
    }
}
