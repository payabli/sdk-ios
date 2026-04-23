import XCTest
@testable import PayabliSDKPayIn

@MainActor
final class CardFormViewModelTests: XCTestCase {

    func testPristineFormReportsNoErrorsUntilTouched() {
        let vm = CardFormViewModel()
        // Empty fields are invalid, but touched-set is empty → no UI errors (FR-4.2).
        XCTAssertNil(vm.errorMessage(for: .holderName))
        XCTAssertNil(vm.errorMessage(for: .cardNumber))
        XCTAssertNil(vm.errorMessage(for: .cvv))
        XCTAssertNil(vm.errorMessage(for: .zip))
        XCTAssertFalse(vm.isValid)
    }

    func testTouchingRevealsErrors() {
        let vm = CardFormViewModel()
        vm.markTouched(.holderName)
        vm.markTouched(.cardNumber)
        XCTAssertNotNil(vm.errorMessage(for: .holderName))
        XCTAssertNotNil(vm.errorMessage(for: .cardNumber))
    }

    func testIsValidAfterFillingEverything() {
        let vm = CardFormViewModel()
        vm.holderName = "Jane Doe"
        vm.cardNumber = "4111111111111111"
        vm.expirationMonth = 12
        vm.expirationYear = 2030
        vm.cvv = "123"
        vm.zip = "90210"
        XCTAssertTrue(vm.isValid)
    }

    func testExpirationStringFormat() {
        let vm = CardFormViewModel()
        vm.expirationMonth = 5
        vm.expirationYear = 2027
        XCTAssertEqual(vm.expirationString, "0527")
    }

    func testBrandUpdatesFromCardNumber() {
        let vm = CardFormViewModel()
        vm.cardNumber = "4111"
        XCTAssertEqual(vm.cardBrand, .visa)
        vm.cardNumber = "6011"
        XCTAssertEqual(vm.cardBrand, .discover)
    }

    func testMakePayloadStripsWhitespaceAndNonDigits() {
        let vm = CardFormViewModel()
        vm.holderName = "  Jane Doe  "
        vm.cardNumber = "4111 1111 1111 1111"
        vm.expirationMonth = 2
        vm.expirationYear = 2028
        vm.cvv = "123"
        vm.zip = "90210-0000"

        let payload = vm.makePayload()
        XCTAssertEqual(payload.cardHolder, "Jane Doe")
        XCTAssertEqual(payload.cardnumber, "4111111111111111")
        XCTAssertEqual(payload.cardexp, "0228")
        XCTAssertEqual(payload.cardcvv, "123")
        XCTAssertEqual(payload.cardzip, "902100000")
    }

    func testSubmissionLifecycle() {
        let vm = CardFormViewModel()
        XCTAssertFalse(vm.isSubmitting)
        vm.beginSubmission()
        XCTAssertTrue(vm.isSubmitting)
        XCTAssertNil(vm.lastError)
        vm.endSubmission(error: "Declined")
        XCTAssertFalse(vm.isSubmitting)
        XCTAssertEqual(vm.lastError, "Declined")
    }
}
