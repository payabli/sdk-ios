import XCTest
@testable import PayabliSDKPayIn

final class PaymentValidatorsTests: XCTestCase {

    // MARK: - Luhn

    func testLuhnAcceptsKnownValidNumbers() {
        XCTAssertTrue(PaymentValidators.isValidCardNumber("4111111111111111"))      // Visa
        XCTAssertTrue(PaymentValidators.isValidCardNumber("5555 5555 5555 4444"))   // Mastercard
        XCTAssertTrue(PaymentValidators.isValidCardNumber("378282246310005"))       // Amex
        XCTAssertTrue(PaymentValidators.isValidCardNumber("6011111111111117"))      // Discover
    }

    func testLuhnRejectsInvalidNumbers() {
        XCTAssertFalse(PaymentValidators.isValidCardNumber("4111111111111112"))
        XCTAssertFalse(PaymentValidators.isValidCardNumber("0000000000000000"))
        XCTAssertFalse(PaymentValidators.isValidCardNumber("abcd"))
        XCTAssertFalse(PaymentValidators.isValidCardNumber("4111"))
    }

    // MARK: - Card brand detection (PRD §10)

    func testCardBrandDetection() {
        XCTAssertEqual(PaymentValidators.cardBrand(for: "4111111111111111"), .visa)
        XCTAssertEqual(PaymentValidators.cardBrand(for: "5555555555554444"), .mastercard)
        XCTAssertEqual(PaymentValidators.cardBrand(for: "378282246310005"), .amex)
        XCTAssertEqual(PaymentValidators.cardBrand(for: "6011111111111117"), .discover)
        XCTAssertEqual(PaymentValidators.cardBrand(for: "2221000000000009"), .mastercard) // BIN range
        XCTAssertEqual(PaymentValidators.cardBrand(for: ""), .unknown)
        XCTAssertEqual(PaymentValidators.cardBrand(for: "9999999999999995"), .unknown)
    }

    // MARK: - CVV

    func testCVVLengthByBrand() {
        XCTAssertTrue(PaymentValidators.isValidCVV("123", brand: .visa))
        XCTAssertTrue(PaymentValidators.isValidCVV("1234", brand: .amex))
        XCTAssertFalse(PaymentValidators.isValidCVV("1234", brand: .visa))
        XCTAssertFalse(PaymentValidators.isValidCVV("12", brand: .visa))
    }

    func testCVVPermissiveMode() {
        XCTAssertTrue(PaymentValidators.isValidCVV("123"))
        XCTAssertTrue(PaymentValidators.isValidCVV("1234"))
        XCTAssertFalse(PaymentValidators.isValidCVV("12"))
        XCTAssertFalse(PaymentValidators.isValidCVV("12345"))
    }

    // MARK: - Expiration

    func testExpirationFutureValid() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 21))!
        XCTAssertTrue(PaymentValidators.isValidExpiration(month: 5, year: 2027, now: now))
        XCTAssertTrue(PaymentValidators.isValidExpiration(month: 4, year: 26, now: now), "2-digit year")
    }

    func testExpirationPastRejected() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 21))!
        XCTAssertFalse(PaymentValidators.isValidExpiration(month: 3, year: 2026, now: now))
        XCTAssertFalse(PaymentValidators.isValidExpiration(month: 1, year: 2020, now: now))
    }

    func testExpirationRejectsInvalidMonths() {
        XCTAssertFalse(PaymentValidators.isValidExpiration(month: 13, year: 2030))
        XCTAssertFalse(PaymentValidators.isValidExpiration(month: 0, year: 2030))
    }

    // MARK: - ZIP / routing / account

    func testZIPValidation() {
        XCTAssertTrue(PaymentValidators.isValidZIP("90210"))
        XCTAssertTrue(PaymentValidators.isValidZIP("90210-1234"))
        XCTAssertFalse(PaymentValidators.isValidZIP("1234"))
    }

    func testRoutingNumberABAChecksum() {
        // Sample valid ABA routing numbers
        XCTAssertTrue(PaymentValidators.isValidRoutingNumber("021000021")) // JP Morgan Chase
        XCTAssertTrue(PaymentValidators.isValidRoutingNumber("011000015")) // Federal Reserve Bank Boston
        // Wrong length
        XCTAssertFalse(PaymentValidators.isValidRoutingNumber("12345678"))
        // Wrong checksum
        XCTAssertFalse(PaymentValidators.isValidRoutingNumber("123456789"))
    }

    func testAccountNumberValidation() {
        XCTAssertTrue(PaymentValidators.isValidAccountNumber("1234"))
        XCTAssertTrue(PaymentValidators.isValidAccountNumber("123456789"))
        XCTAssertFalse(PaymentValidators.isValidAccountNumber("123"))
    }

    func testHolderNameValidation() {
        XCTAssertTrue(PaymentValidators.isValidHolderName("Jane Doe"))
        XCTAssertFalse(PaymentValidators.isValidHolderName(""))
        XCTAssertFalse(PaymentValidators.isValidHolderName("   "))
    }

    // MARK: - Card number formatting

    func testFormatCardNumberVisa() {
        XCTAssertEqual(
            PaymentValidators.formatCardNumber("4242424242424242", brand: .visa),
            "4242 4242 4242 4242"
        )
    }

    func testFormatCardNumberAmexUsesFourSixFive() {
        XCTAssertEqual(
            PaymentValidators.formatCardNumber("378282246310005", brand: .amex),
            "3782 822463 10005"
        )
    }

    func testFormatCardNumberIdempotent() {
        let once = PaymentValidators.formatCardNumber("4242424242424242", brand: .visa)
        let twice = PaymentValidators.formatCardNumber(once, brand: .visa)
        XCTAssertEqual(once, twice)
    }

    func testFormatCardNumberStripsNonDigits() {
        XCTAssertEqual(
            PaymentValidators.formatCardNumber("4242-abc-4242 4242", brand: .visa),
            "4242 4242 4242"
        )
    }

    func testFormatCardNumberPartialInput() {
        XCTAssertEqual(PaymentValidators.formatCardNumber("4242", brand: .visa), "4242")
        XCTAssertEqual(PaymentValidators.formatCardNumber("42421", brand: .visa), "4242 1")
        XCTAssertEqual(PaymentValidators.formatCardNumber("", brand: .visa), "")
    }

    func testMaxDigits() {
        XCTAssertEqual(PaymentValidators.maxDigits(for: .amex), 15)
        XCTAssertEqual(PaymentValidators.maxDigits(for: .mastercard), 16)
        XCTAssertEqual(PaymentValidators.maxDigits(for: .visa), 16)
        XCTAssertEqual(PaymentValidators.maxDigits(for: .discover), 16)
        XCTAssertEqual(PaymentValidators.maxDigits(for: .unknown), 16)
    }

    func testAutoAdvanceDigits() {
        XCTAssertEqual(PaymentValidators.autoAdvanceDigits(for: .visa), 16)
        XCTAssertEqual(PaymentValidators.autoAdvanceDigits(for: .amex), 15)
        XCTAssertNil(PaymentValidators.autoAdvanceDigits(for: .unknown))
    }

    func testCvvLength() {
        XCTAssertEqual(PaymentValidators.cvvLength(for: .amex), 4)
        XCTAssertEqual(PaymentValidators.cvvLength(for: .visa), 3)
    }
}
