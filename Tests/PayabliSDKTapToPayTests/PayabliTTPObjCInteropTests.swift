@testable import PayabliSDKTapToPay
import XCTest

/// Round-trip tests for the ObjC companion classes that wrap
/// `PayabliTTPCustomerData`, `PayabliTTPPaymentDetails`,
/// `PayabliTTPInvoiceData`, and `TransactionResult`.
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
            phone: "+1-415-555-0100",
            customerId: nil,
            company: nil,
            billingAddress1: nil, billingAddress2: nil,
            billingCity: nil, billingState: nil,
            billingZip: nil, billingCountry: nil,
            billingPhone: nil, billingEmail: nil,
            shippingAddress1: nil, shippingAddress2: nil,
            shippingCity: nil, shippingState: nil,
            shippingZip: nil, shippingCountry: nil
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
            email: nil, phone: nil,
            customerId: nil,
            company: nil,
            billingAddress1: nil, billingAddress2: nil,
            billingCity: nil, billingState: nil,
            billingZip: nil, billingCountry: nil,
            billingPhone: nil, billingEmail: nil,
            shippingAddress1: nil, shippingAddress2: nil,
            shippingCity: nil, shippingState: nil,
            shippingZip: nil, shippingCountry: nil
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
            email: nil, phone: nil,
            customerId: nil,
            company: nil,
            billingAddress1: nil, billingAddress2: nil,
            billingCity: nil, billingState: nil,
            billingZip: nil, billingCountry: nil,
            billingPhone: nil, billingEmail: nil,
            shippingAddress1: nil, shippingAddress2: nil,
            shippingCity: nil, shippingState: nil,
            shippingZip: nil, shippingCountry: nil
        )

        let swift = objc.toSwift()
        XCTAssertEqual(swift.firstName, "Ada")
        XCTAssertNil(swift.lastName)
        XCTAssertNil(swift.customerNumber)
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
        // currency defaults to nil so the wire JSON omits the field and the
        // backend authorizes in the merchant's configured processor currency.
        XCTAssertNil(details.currency)
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

    func testPaymentDetailsSwiftDropsBlankCurrency() {
        let details = PayabliTTPPaymentDetails(
            amount: 10,
            currency: "   "
        )
        XCTAssertNil(details.currency)
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

    // MARK: - PayabliTTPInvoiceData

    func testInvoiceDataSwiftDefaults() {
        let invoice = PayabliTTPInvoiceData()
        XCTAssertNil(invoice.invoiceNumber)
        XCTAssertTrue(invoice.isEmpty)
    }

    func testInvoiceDataSwiftSanitizesInvoiceNumber() {
        let invoice = PayabliTTPInvoiceData(invoiceNumber: "  INV-1  ")
        XCTAssertEqual(invoice.invoiceNumber, "INV-1")
        XCTAssertFalse(invoice.isEmpty)
    }

    func testInvoiceDataSwiftDropsBlankInvoiceNumber() {
        let invoice = PayabliTTPInvoiceData(invoiceNumber: "   ")
        XCTAssertNil(invoice.invoiceNumber)
    }

    func testInvoiceDataObjCRoundTrip() {
        let objc = PayabliTTPInvoiceDataObjC(invoiceNumber: "INV-1001")
        XCTAssertEqual(objc.invoiceNumber, "INV-1001")
        XCTAssertEqual(objc.toSwift().invoiceNumber, "INV-1001")
    }

    func testInvoiceDataObjCAcceptsNil() {
        let objc = PayabliTTPInvoiceDataObjC(invoiceNumber: nil)
        XCTAssertNil(objc.invoiceNumber)
        XCTAssertTrue(objc.toSwift().isEmpty)
    }

    // MARK: - PayabliTTPCustomerData expanded fields

    func testCustomerDataSwiftAcceptsCustomerIdAndCompany() {
        let customer = PayabliTTPCustomerData(
            firstName: "Ana",
            customerId: 12345,
            company: "Acme Inc"
        )
        XCTAssertEqual(customer.customerId, 12345)
        XCTAssertEqual(customer.company, "Acme Inc")
    }

    func testCustomerDataSwiftAcceptsBillingBlock() {
        let customer = PayabliTTPCustomerData(
            billingAddress1: "1 Market St",
            billingAddress2: "Apt 5",
            billingCity: "San Francisco",
            billingState: "CA",
            billingZip: "94105",
            billingCountry: "US",
            billingPhone: "+1-415-555-0100",
            billingEmail: "ana@example.com"
        )
        XCTAssertEqual(customer.billingAddress1, "1 Market St")
        XCTAssertEqual(customer.billingAddress2, "Apt 5")
        XCTAssertEqual(customer.billingCity, "San Francisco")
        XCTAssertEqual(customer.billingState, "CA")
        XCTAssertEqual(customer.billingZip, "94105")
        XCTAssertEqual(customer.billingCountry, "US")
        XCTAssertEqual(customer.billingPhone, "+1-415-555-0100")
        XCTAssertEqual(customer.billingEmail, "ana@example.com")
    }

    func testCustomerDataSwiftAcceptsShippingBlock() {
        let customer = PayabliTTPCustomerData(
            shippingAddress1: "2 Pine St",
            shippingAddress2: "Suite 9",
            shippingCity: "Oakland",
            shippingState: "CA",
            shippingZip: "94607",
            shippingCountry: "US"
        )
        XCTAssertEqual(customer.shippingAddress1, "2 Pine St")
        XCTAssertEqual(customer.shippingAddress2, "Suite 9")
        XCTAssertEqual(customer.shippingCity, "Oakland")
        XCTAssertEqual(customer.shippingState, "CA")
        XCTAssertEqual(customer.shippingZip, "94607")
        XCTAssertEqual(customer.shippingCountry, "US")
    }

    func testCustomerDataSwiftSanitizesNewStringFields() {
        let customer = PayabliTTPCustomerData(
            company: "  Acme  ",
            billingAddress1: "   ",
            billingCity: ""
        )
        XCTAssertEqual(customer.company, "Acme")
        XCTAssertNil(customer.billingAddress1)
        XCTAssertNil(customer.billingCity)
    }

    func testCustomerDataObjCRoundTripsCustomerIdAsNSNumber() {
        let objc = PayabliTTPCustomerDataObjC(
            firstName: nil, lastName: nil, customerNumber: nil,
            email: nil, phone: nil,
            customerId: NSNumber(value: 99),
            company: "Acme",
            billingAddress1: "1 Market",
            billingAddress2: nil,
            billingCity: "SF",
            billingState: "CA",
            billingZip: "94105",
            billingCountry: "US",
            billingPhone: nil,
            billingEmail: nil,
            shippingAddress1: nil,
            shippingAddress2: nil,
            shippingCity: nil,
            shippingState: nil,
            shippingZip: nil,
            shippingCountry: nil
        )
        XCTAssertEqual(objc.customerId, NSNumber(value: 99))
        XCTAssertEqual(objc.company, "Acme")
        XCTAssertEqual(objc.billingCity, "SF")

        let swift = objc.toSwift()
        XCTAssertEqual(swift.customerId, 99)
        XCTAssertEqual(swift.company, "Acme")
        XCTAssertEqual(swift.billingCity, "SF")
        XCTAssertNil(swift.billingPhone)
    }

    func testCustomerDataObjCNilCustomerIdMapsToSwiftNil() {
        let objc = PayabliTTPCustomerDataObjC(
            firstName: nil, lastName: nil, customerNumber: nil,
            email: nil, phone: nil,
            customerId: nil,
            company: nil,
            billingAddress1: nil, billingAddress2: nil,
            billingCity: nil, billingState: nil,
            billingZip: nil, billingCountry: nil,
            billingPhone: nil, billingEmail: nil,
            shippingAddress1: nil, shippingAddress2: nil,
            shippingCity: nil, shippingState: nil,
            shippingZip: nil, shippingCountry: nil
        )
        XCTAssertNil(objc.customerId)
        XCTAssertNil(objc.toSwift().customerId)
    }

    /// Regression: bridging from `NSNumber` to Swift `Int` must preserve
    /// 64-bit values. Using `NSNumber.intValue` (Int32) would silently
    /// truncate any customer record id above `Int32.max`, attaching the
    /// charge to the wrong customer.
    func testCustomerDataObjCCustomerIdPreserves64BitValue() {
        let big = Int64(Int32.max) + 1 // 2_147_483_648 — overflows Int32
        let objc = PayabliTTPCustomerDataObjC(
            firstName: nil, lastName: nil, customerNumber: nil,
            email: nil, phone: nil,
            customerId: NSNumber(value: big),
            company: nil,
            billingAddress1: nil, billingAddress2: nil,
            billingCity: nil, billingState: nil,
            billingZip: nil, billingCountry: nil,
            billingPhone: nil, billingEmail: nil,
            shippingAddress1: nil, shippingAddress2: nil,
            shippingCity: nil, shippingState: nil,
            shippingZip: nil, shippingCountry: nil
        )
        XCTAssertEqual(objc.toSwift().customerId, Int(big))
    }
}
