@testable import PayabliSDKPayIn
import XCTest

/// What a success screen shows: the result's code and identifiers, never the service's text.
final class PayInOutcomeRowsTests: XCTestCase {
    func testAStoredMethodShowsItsCodeAndIdAndNothingElse() {
        let stored = PayabliPayInStoredMethod(
            storedMethodId: "stored-123",
            method: .card,
            methodReferenceId: "method-123",
            customerId: 4440
        )

        let outcome = PayInOutcome(.method(stored))

        XCTAssertEqual(outcome.summaryRows.map(\.label), ["Code", "Stored method ID"])
        XCTAssertEqual(outcome.summaryRows.map(\.value), ["1", "stored-123"])
        XCTAssertEqual(outcome.headline, "Code 1")
    }

    func testAPaymentShowsItsCodeIdentifiersAndAmountsAndNoServiceText() {
        let response = PayabliPayInAPIResponse(
            code: "A0000",
            reason: "service-reason",
            explanation: "service-explanation",
            action: "service-action",
            data: PayabliPayInTransaction(
                paymentTransId: "pay-123",
                gatewayTransId: "gw-123",
                orderId: "order-123",
                method: "card",
                transStatus: 1,
                totalAmount: 10,
                feeAmount: 1,
                operation: "Sale",
                source: "api"
            )
        )

        let outcome = PayInOutcome(.payment(PayabliPayInResult(apiResponse: response)))

        XCTAssertEqual(outcome.summaryRows.map(\.label), [
            "Code", "Payment trans ID", "Gateway trans ID", "Order ID", "Method", "Operation",
            "Status", "Total amount", "Fee amount", "Source"
        ])
        XCTAssertEqual(
            Array(outcome.summaryRows.map(\.value).prefix(7)),
            ["A0000", "pay-123", "gw-123", "order-123", "card", "Sale", "1"]
        )
        XCTAssertEqual(outcome.summaryRows.last?.value, "api")
        XCTAssertEqual(outcome.headline, "Code A0000")
        let shown = outcome.summaryRows.map(\.value) + [outcome.headline]
        for serviceText in ["service-reason", "service-explanation", "service-action"] {
            XCTAssertFalse(shown.contains { $0.contains(serviceText) }, serviceText)
        }
    }
}
