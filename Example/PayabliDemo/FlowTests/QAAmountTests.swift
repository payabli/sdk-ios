import XCTest

final class QAAmountTests: XCTestCase {
    func testEveryAmountIsInsideTheRangeAndIsWholeCents() {
        // Swept rather than sampled: a bound off by a cent shows up in one draw out of thirteen hundred.
        for _ in 0 ..< 10000 {
            let amount = QAAmount.random()

            XCTAssertGreaterThanOrEqual(amount, 2, "\(amount) is below two dollars")
            XCTAssertLessThan(amount, 15, "\(amount) is fifteen dollars or more")
            XCTAssertEqual((amount * 100).rounded(), amount * 100, accuracy: 0.001, "\(amount) is not whole cents")
        }
    }

    func testTwoAttemptsDiffer() {
        // The reason the figure is randomized at all: two rows from one device have to tell themselves apart.
        let drawn = (0 ..< 20).map { _ in QAAmount.random() }

        XCTAssertGreaterThan(Set(drawn).count, 1, "twenty draws produced \(drawn)")
    }
}
