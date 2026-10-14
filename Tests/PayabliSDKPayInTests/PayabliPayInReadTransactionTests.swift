import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

@MainActor
final class PayabliPayInReadTransactionTests: XCTestCase {
    func testAReadIsRefusedBeforeAnythingIsSent() async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "unused")

        do {
            _ = try await flow.readTransaction("trans-1")
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual((error as? any PayabliError)?.type, .sdkInternalError)
        }
        XCTAssertEqual(transport.count, 0)
    }
}

final class PayabliPayInTransactionObjCTests: XCTestCase {
    func testTheObjectiveCTransactionCarriesTheStatusByName() {
        let transaction = PayabliPayInTransactionObjC(
            PayabliPayInTransaction(paymentTransId: "trans-1", transStatus: 5, totalAmount: 1.10)
        )

        XCTAssertEqual(transaction.paymentTransId, "trans-1")
        XCTAssertEqual(transaction.transStatus, 5)
        XCTAssertEqual(transaction.status, "voided")
        XCTAssertEqual(transaction.totalAmount, 1.10)
    }

    func testAnUnnamedStatusIsOtherAndKeepsItsNumber() {
        let transaction = PayabliPayInTransactionObjC(PayabliPayInTransaction(transStatus: 99))

        XCTAssertEqual(transaction.status, "other")
        XCTAssertEqual(transaction.transStatus, 99)
    }

    func testNoStatusNumberIsNoStatus() {
        XCTAssertNil(PayabliPayInTransactionObjC(PayabliPayInTransaction()).status)
    }
}
