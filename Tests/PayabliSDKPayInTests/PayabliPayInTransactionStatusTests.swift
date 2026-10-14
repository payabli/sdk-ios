import PayabliSDKPayIn
import XCTest

final class PayabliPayInTransactionStatusTests: XCTestCase {
    func testEachStatusNumberIsReadByItsOwnRow() {
        let table: [(Int, PayabliPayInTransactionStatus)] = [
            (10, .initiated),
            (11, .authorized),
            (1, .captured),
            (2, .declined),
            (3, .declined),
            (5, .voided),
            (-2, .returned),
            (-1, .failed),
            (0, .failed)
        ]
        for (wire, expected) in table {
            XCTAssertEqual(PayabliPayInTransaction(transStatus: wire).status, expected, "wire \(wire)")
        }
    }

    func testANumberWithNoRowKeepsTheNumber() {
        for wire in [4, 6, 12, 99, -3, -4, -5, -6, -7, Int.max, Int.min] {
            XCTAssertEqual(PayabliPayInTransaction(transStatus: wire).status, .other(wire), "wire \(wire)")
        }
    }

    func testNoStatusNumberIsNoStatus() {
        XCTAssertNil(PayabliPayInTransaction(transStatus: nil).status)
    }
}
