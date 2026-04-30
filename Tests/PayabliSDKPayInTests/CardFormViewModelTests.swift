import XCTest
@testable import PayabliSDKPayIn
import PayabliSDKCore

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
        vm.endSubmission(error: PayabliGenericError(code: .unknown, reason: "Declined"))
        XCTAssertFalse(vm.isSubmitting)
        XCTAssertEqual(vm.lastError, "Declined")
    }

    func testEndSubmissionMapsPaymentErrorReason() throws {
        let json = Data(#"{"code":"D0001","reason":"Do not honor"}"#.utf8)
        let decline = try JSONDecoder().decode(PayabliDeclineError.self, from: json)

        let vm = CardFormViewModel()
        vm.beginSubmission()
        vm.endSubmission(error: PayabliPaymentError.decline(decline))
        XCTAssertEqual(vm.lastError, "Do not honor")
    }

    // MARK: - Auto-format

    func testCardNumberAutoFormatsVisa() {
        let vm = CardFormViewModel()
        vm.cardNumber = "4242424242424242"
        XCTAssertEqual(vm.cardNumber, "4242 4242 4242 4242")
    }

    func testCardNumberAutoFormatsAmexAsFourSixFive() {
        let vm = CardFormViewModel()
        vm.cardNumber = "378282246310005"
        XCTAssertEqual(vm.cardNumber, "3782 822463 10005")
    }

    func testCardNumberCappedAtBrandMax() {
        let vm = CardFormViewModel()
        vm.cardNumber = "3782822463100059999" // 19 digits, Amex caps at 15
        XCTAssertEqual(vm.cardNumber.filter(\.isNumber).count, 15)
    }

    func testCvvCappedByBrand() {
        let vm = CardFormViewModel()
        vm.cardNumber = "4242424242424242" // Visa → CVV max 3
        vm.cvv = "12345"
        XCTAssertEqual(vm.cvv, "123")

        vm.cardNumber = "378282246310005" // Amex → CVV max 4
        vm.cvv = "12345"
        XCTAssertEqual(vm.cvv, "1234")
    }

    // MARK: - Expiration text auto-format

    func testExpirationTextInsertsSlashAfterTwoDigits() {
        let vm = CardFormViewModel()
        vm.expirationText = "12"
        XCTAssertEqual(vm.expirationText, "12")
        vm.expirationText = "125"
        XCTAssertEqual(vm.expirationText, "12 / 5")
        vm.expirationText = "1225"
        XCTAssertEqual(vm.expirationText, "12 / 25")
    }

    func testExpirationTextSyncsMonthAndYear() {
        let vm = CardFormViewModel()
        vm.expirationText = "0527"
        XCTAssertEqual(vm.expirationMonth, 5)
        XCTAssertEqual(vm.expirationYear, 2027)
    }

    func testExpirationTextStripsNonDigitsAndCaps() {
        let vm = CardFormViewModel()
        vm.expirationText = "ab12-34cd"
        XCTAssertEqual(vm.expirationText, "12 / 34")
    }

    func testExpirationCappedAtFourDigitsOnPaste() {
        let vm = CardFormViewModel()
        vm.expirationText = "1234567890"
        XCTAssertEqual(vm.expirationText, "12 / 34")
        XCTAssertEqual(vm.expirationText.filter(\.isNumber).count, 4)
    }

    func testCvvBrandAwareCapOnPaste() {
        let vm = CardFormViewModel()
        // Visa → 3-digit cap.
        vm.cardNumber = "4242424242424242"
        vm.cvv = "123456789"
        XCTAssertEqual(vm.cvv, "123")

        // Amex → 4-digit cap.
        vm.cardNumber = "378282246310005"
        vm.cvv = "123456789"
        XCTAssertEqual(vm.cvv, "1234")
    }

    func testCardNumberCappedToBrandMaxOnPaste() {
        let vm = CardFormViewModel()
        vm.cardNumber = "37828224631000599999999"  // Amex BIN, way over 15 digits
        XCTAssertEqual(vm.cardNumber.filter(\.isNumber).count, 15)
        XCTAssertEqual(vm.cardNumber, "3782 822463 10005")
    }

    func testVisaCappedAtSixteenDigits() {
        let vm = CardFormViewModel()
        vm.cardNumber = "4242424242424242999"  // 19 digits, Visa BIN
        XCTAssertEqual(vm.cardNumber.filter(\.isNumber).count, 16)
        XCTAssertEqual(vm.cardNumber, "4242 4242 4242 4242")
    }

    func testDiscoverCappedAtSixteenDigits() {
        let vm = CardFormViewModel()
        vm.cardNumber = "6011000990139424999"  // 19 digits, Discover BIN
        XCTAssertEqual(vm.cardNumber.filter(\.isNumber).count, 16)
        XCTAssertEqual(vm.cardNumber, "6011 0009 9013 9424")
    }

    func testUnknownBrandCappedAtSixteenDigits() {
        let vm = CardFormViewModel()
        vm.cardNumber = "9999999999999999999"  // 19 digits, unknown BIN
        XCTAssertEqual(vm.cardNumber.filter(\.isNumber).count, 16)
    }

    // MARK: - Append-beyond-cap (user taps back into a full field)

    func testExpirationRejectsAppendBeyondFourDigits() {
        let vm = CardFormViewModel()
        vm.expirationText = "1234"
        XCTAssertEqual(vm.expirationText, "12 / 34")

        // User taps back in and types a 5th digit at the end.
        vm.expirationText = "12 / 345"
        XCTAssertEqual(vm.expirationText, "12 / 34")
        XCTAssertEqual(vm.expirationText.filter(\.isNumber).count, 4)
    }

    func testCvvRejectsAppendBeyondCapForVisa() {
        let vm = CardFormViewModel()
        vm.cardNumber = "4242424242424242"
        vm.cvv = "123"
        XCTAssertEqual(vm.cvv, "123")

        vm.cvv = "1234"
        XCTAssertEqual(vm.cvv, "123")
    }

    func testCvvRejectsAppendBeyondCapForAmex() {
        let vm = CardFormViewModel()
        vm.cardNumber = "378282246310005"
        vm.cvv = "1234"
        XCTAssertEqual(vm.cvv, "1234")

        vm.cvv = "12345"
        XCTAssertEqual(vm.cvv, "1234")
    }

    // MARK: - Customization (strings + allowedBrands)

    func testCustomStringsDriveValidationErrors() {
        let vm = CardFormViewModel()
        vm.strings = CardFormStrings(
            holderNameError: "Nombre requerido",
            cardNumberError: "Numero invalido",
            expirationError: "Fecha invalida",
            cvcError: "CVC invalido",
            zipError: "ZIP invalido"
        )
        for field in CardFormViewModel.Field.allCases {
            vm.markTouched(field)
        }

        XCTAssertEqual(vm.errorMessage(for: .holderName), "Nombre requerido")
        XCTAssertEqual(vm.errorMessage(for: .cardNumber), "Numero invalido")
        XCTAssertEqual(vm.errorMessage(for: .expiration), "Fecha invalida")
        XCTAssertEqual(vm.errorMessage(for: .cvv), "CVC invalido")
        XCTAssertEqual(vm.errorMessage(for: .zip), "ZIP invalido")
    }

    func testDisallowedBrandFailsValidation() {
        let vm = CardFormViewModel()
        vm.allowedBrands = [.visa, .mastercard]   // no Amex
        vm.cardNumber = "378282246310005"          // valid Amex PAN
        vm.markTouched(.cardNumber)

        XCTAssertEqual(
            vm.errorMessage(for: .cardNumber),
            CardFormStrings.default.disallowedBrandError
        )
        XCTAssertFalse(vm.isValid)
    }

    func testDisallowedBrandSurfacesCustomString() {
        let vm = CardFormViewModel()
        vm.allowedBrands = [.visa]
        vm.strings = CardFormStrings(disallowedBrandError: "Marca no aceptada")
        vm.cardNumber = "5555555555554444"  // Mastercard
        vm.markTouched(.cardNumber)

        XCTAssertEqual(vm.errorMessage(for: .cardNumber), "Marca no aceptada")
    }

    func testAllowedBrandStillValidatesLuhn() {
        let vm = CardFormViewModel()
        vm.allowedBrands = .all
        vm.cardNumber = "4242424242424241"  // Visa BIN, fails Luhn
        vm.markTouched(.cardNumber)

        XCTAssertEqual(
            vm.errorMessage(for: .cardNumber),
            CardFormStrings.default.cardNumberError
        )
    }

    func testUnknownBrandIsNotBlockedWhilePartiallyEntered() {
        let vm = CardFormViewModel()
        vm.allowedBrands = [.visa]
        vm.cardNumber = "9"  // not yet a recognized BIN
        vm.markTouched(.cardNumber)

        // Brand check is `unknown` → passes; only the Luhn check should fail.
        XCTAssertEqual(
            vm.errorMessage(for: .cardNumber),
            CardFormStrings.default.cardNumberError
        )
    }

    func testAllowedBrandsAllContainsEveryBrand() {
        XCTAssertTrue(PayabliCardBrand.all.allows(.visa))
        XCTAssertTrue(PayabliCardBrand.all.allows(.mastercard))
        XCTAssertTrue(PayabliCardBrand.all.allows(.amex))
        XCTAssertTrue(PayabliCardBrand.all.allows(.discover))
        XCTAssertTrue(PayabliCardBrand.all.allows(.unknown))

        let visaOnly: PayabliCardBrand = .visa
        XCTAssertTrue(visaOnly.allows(.visa))
        XCTAssertFalse(visaOnly.allows(.mastercard))
        XCTAssertFalse(visaOnly.allows(.amex))
        XCTAssertFalse(visaOnly.allows(.discover))
        XCTAssertTrue(visaOnly.allows(.unknown))  // still unblocked
    }
}
