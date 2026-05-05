import XCTest
@testable import PayabliSDKTapToPay

/// Round-trip tests for the ObjC companion classes that wrap
/// `PayabliTTPCustomerData`, `PayabliTTPOrderData`, and `TransactionResult`.
///
/// These tests guard the contract documented in
/// `PayabliTTPTransactionData+ObjC.swift`: that the `*ObjC` companion classes
/// hold the same fields with the same labels as the Swift structs and that
/// `toSwift()` produces an equivalent value.
final class PayabliTTPObjCInteropTests: XCTestCase {

    // MARK: - PayabliTTPCustomerDataObjC

    func testCustomerDataObjCRoundTripPreservesAllFields() {
        let objc = PayabliTTPCustomerDataObjC(
            firstName: "Ada",
            lastName: "Lovelace",
            customerNumber: "C-42",
            email: "ada@example.com",
            phone: "+1-415-555-0100"
        )

        XCTAssertEqual(objc.firstName, "Ada")
        XCTAssertEqual(objc.lastName, "Lovelace")
        XCTAssertEqual(objc.customerNumber, "C-42")
        XCTAssertEqual(objc.email, "ada@example.com")
        XCTAssertEqual(objc.phone, "+1-415-555-0100")

        let swift = objc.toSwift()
        XCTAssertEqual(swift.firstName, "Ada")
        XCTAssertEqual(swift.lastName, "Lovelace")
        XCTAssertEqual(swift.customerNumber, "C-42")
        XCTAssertEqual(swift.email, "ada@example.com")
        XCTAssertEqual(swift.phone, "+1-415-555-0100")
    }

    func testCustomerDataObjCAcceptsAllNilFields() {
        let objc = PayabliTTPCustomerDataObjC(
            firstName: nil, lastName: nil, customerNumber: nil,
            email: nil, phone: nil
        )

        XCTAssertNil(objc.firstName)
        XCTAssertNil(objc.lastName)
        XCTAssertNil(objc.customerNumber)
        XCTAssertNil(objc.email)
        XCTAssertNil(objc.phone)

        XCTAssertTrue(objc.toSwift().isEmpty)
    }

    func testCustomerDataObjCSwiftRoundTripPreservesSanitization() {
        // The Swift struct trims whitespace; the companion does not, but the
        // bridge through `toSwift()` should give the trimmed output.
        let objc = PayabliTTPCustomerDataObjC(
            firstName: "  Ada  ", lastName: "", customerNumber: "  ",
            email: nil, phone: nil
        )

        let swift = objc.toSwift()
        XCTAssertEqual(swift.firstName, "Ada")
        XCTAssertNil(swift.lastName)
        XCTAssertNil(swift.customerNumber)
    }

    // MARK: - PayabliTTPOrderDataObjC

    func testOrderDataObjCRoundTripPreservesAllFields() {
        let objc = PayabliTTPOrderDataObjC(
            orderId: "O-1",
            orderDescription: "Coffee + croissant",
            invoiceNumber: "INV-1001"
        )

        XCTAssertEqual(objc.orderId, "O-1")
        XCTAssertEqual(objc.orderDescription, "Coffee + croissant")
        XCTAssertEqual(objc.invoiceNumber, "INV-1001")

        let swift = objc.toSwift()
        XCTAssertEqual(swift.orderId, "O-1")
        XCTAssertEqual(swift.orderDescription, "Coffee + croissant")
        XCTAssertEqual(swift.invoiceNumber, "INV-1001")
    }

    func testOrderDataObjCAcceptsAllNilFields() {
        let objc = PayabliTTPOrderDataObjC(
            orderId: nil, orderDescription: nil, invoiceNumber: nil
        )

        XCTAssertNil(objc.orderId)
        XCTAssertNil(objc.orderDescription)
        XCTAssertNil(objc.invoiceNumber)
        XCTAssertTrue(objc.toSwift().isEmpty)
    }

    // MARK: - PayabliTTPTransactionResultObjC

    func testTransactionResultObjCWrapsSwiftValue() {
        let swift = TransactionResult(paymentTransId: "TXN-12345")
        let objc = PayabliTTPTransactionResultObjC(swift)

        XCTAssertEqual(objc.paymentTransId, "TXN-12345")
    }

    // MARK: - PayabliTTPEventToken

    func testEventTokenCancelIsIdempotent() {
        let token = PayabliTTPEventToken(task: Task<Void, Never> {
            try? await Task.sleep(nanoseconds: UInt64.max)
        })

        token.cancel()
        token.cancel() // must not crash

        XCTAssertTrue(token.task.isCancelled)
    }

    // MARK: - PayabliTTPPaymentDetails

    func testPaymentDetailsSwiftDefaults() {
        let details = PayabliTTPPaymentDetails(amount: 25.00)
        XCTAssertEqual(details.amount, 25.00)
        XCTAssertEqual(details.serviceFee, 0)
        XCTAssertEqual(details.currency, "USD")
        XCTAssertNil(details.paymentDescription)
    }

    func testPaymentDetailsSwiftSanitizesCurrencyAndDescription() {
        let details = PayabliTTPPaymentDetails(
            amount: 10,
            serviceFee: 1,
            currency: "  usd  ",
            paymentDescription: "  Coffee  "
        )
        XCTAssertEqual(details.currency, "USD")
        XCTAssertEqual(details.paymentDescription, "Coffee")
    }

    func testPaymentDetailsSwiftDropsBlankPaymentDescription() {
        let details = PayabliTTPPaymentDetails(
            amount: 10,
            paymentDescription: "   "
        )
        XCTAssertNil(details.paymentDescription)
    }

    func testPaymentDetailsObjCRoundTripPreservesAllFields() {
        let objc = PayabliTTPPaymentDetailsObjC(
            amount: NSDecimalNumber(string: "25.00"),
            serviceFee: NSDecimalNumber(string: "1.50"),
            currency: "USD",
            paymentDescription: "Coffee"
        )
        XCTAssertEqual(objc.amount, NSDecimalNumber(string: "25.00"))
        XCTAssertEqual(objc.serviceFee, NSDecimalNumber(string: "1.50"))
        XCTAssertEqual(objc.currency, "USD")
        XCTAssertEqual(objc.paymentDescription, "Coffee")

        let swift = objc.toSwift()
        XCTAssertEqual(swift.amount, Decimal(string: "25.00"))
        XCTAssertEqual(swift.serviceFee, Decimal(string: "1.50"))
        XCTAssertEqual(swift.currency, "USD")
        XCTAssertEqual(swift.paymentDescription, "Coffee")
    }
}
