@testable import PayabliSDKPayIn
import XCTest

/// The three promises: nothing leaks through a message, a close overwrites, and a copy is not an alias.
final class SensitiveDigitsTests: XCTestCase {
    private let pan = "4111111111111111"
    private struct Sentinel: Error {}

    func testClosingOverwritesEveryByte() {
        let value = SensitiveDigits.ofString(pan)

        value.close()

        // read() answers empty once wiped, so it cannot show whether the overwrite happened.
        XCTAssertTrue(value.rawCopy().allSatisfy { $0 == SensitiveDigits.wipedByte })
        XCTAssertTrue(value.isWiped)
    }

    func testClosingTwiceIsNotAnError() {
        let value = SensitiveDigits.ofString(pan)

        value.close()
        value.close()

        XCTAssertTrue(value.isWiped)
    }

    func testAClosedValueReadsAsEmptyRatherThanThrowing() {
        // A request built from a closed value has to fail validation as a missing field, not blow up inside
        // an encoder.
        let value = SensitiveDigits.ofString(pan)

        value.close()

        XCTAssertEqual(0, value.length)
        XCTAssertTrue(value.read().isEmpty)
    }

    func testTheSourceArrayIsCopiedSoTheCallerCanWipeItsOwn() {
        var source = Array(pan.utf8)
        let value = SensitiveDigits.of(source)

        for index in source.indices {
            source[index] = SensitiveDigits.wipedByte
        }

        XCTAssertEqual(pan.count, value.length)
        XCTAssertEqual(Array(pan.utf8), value.read())
    }

    func testWipingTheValueLeavesTheCallersArrayAlone() {
        let source = Array(pan.utf8)
        let value = SensitiveDigits.of(source)

        value.close()

        XCTAssertEqual(Array(pan.utf8), source)
    }

    func testReadHandsOutACopyRatherThanTheBuffer() {
        let value = SensitiveDigits.ofString(pan)

        var handedOut = value.read()
        for index in handedOut.indices {
            handedOut[index] = 7
        }

        XCTAssertEqual(Array(pan.utf8), value.read())
    }

    func testDescriptionCarriesTheLengthAndNoDigits() {
        let value = SensitiveDigits.ofString(pan)

        XCTAssertEqual("SensitiveDigits(length=16)", value.description)
        XCTAssertFalse(value.description.contains("4111"))
        // The debug route renders the same redacted text, which is what String(reflecting:) and a
        // debugger's po reach.
        XCTAssertEqual(value.description, value.debugDescription)
        XCTAssertEqual(value.description, String(reflecting: value))
    }

    func testUseDigitBytesDropsSeparatorsAndLeavesTheValueUsable() {
        // The one rule the validators and the body writer share: a spaced card number is read as its
        // digits, and the value itself is untouched by the read.
        let value = SensitiveDigits.ofString("4111 1111 1111 1111")
        var lent: [UInt8]?

        let length = try? value.useDigitBytes(field: "Card number") { digits -> Int in
            lent = digits
            return digits.count
        }

        XCTAssertEqual(16, length)
        XCTAssertEqual(Array("4111111111111111".utf8), lent)
        // The value itself is untouched: lending the digits is not closing them, spaces and all.
        XCTAssertEqual(Array("4111 1111 1111 1111".utf8), value.read())
        XCTAssertFalse(value.isWiped)
        XCTAssertEqual("4111 1111 1111 1111".count, value.length)
    }

    func testUseDigitBytesRefusesAByteThatIsNotAscii() {
        // A digit-shaped character from another script is not the digit it resembles, so it is refused
        // rather than read as one.
        let value = SensitiveDigits.ofString("٤" + String(repeating: "١", count: 15))

        do {
            _ = try value.useDigitBytes(field: "Card number") { _ in
                XCTFail("A refused value never runs the rule")
            }
            XCTFail("Expected a refusal")
        } catch let PayabliPayInTokenStorageError.invalidInput(message) {
            XCTAssertEqual(message, "Card number contains unsupported characters.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        // The refusal leaves the value itself untouched, so a corrected attempt can read it again.
        // Sixteen characters, each two bytes as UTF-8: the value keeps them all.
        XCTAssertFalse(value.isWiped)
        XCTAssertEqual(32, value.length)
    }

    func testUseDigitBytesRethrowsAndLeavesTheValueUntouched() {
        // What is asserted is the contract every reader relies on: the rule's error is rethrown and
        // the value itself is untouched.
        let value = SensitiveDigits.ofString(pan)

        XCTAssertThrowsError(try value.useDigitBytes(field: "Card number") { _ in
            throw Sentinel()
        })

        XCTAssertEqual(Array(pan.utf8), value.read())
        XCTAssertFalse(value.isWiped)
        XCTAssertEqual(pan.count, value.length)
    }

    func testAnEmptyValueIsAllowedHereAndRefusedByValidation() {
        // Constructing one is not the place to reject it: a caller passing a blank field deserves a typed
        // validation failure naming the field, not an exception from a factory.
        let value = SensitiveDigits.ofString("")

        XCTAssertEqual(0, value.length)
    }
}
