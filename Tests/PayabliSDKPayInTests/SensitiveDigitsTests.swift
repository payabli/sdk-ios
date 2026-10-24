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
        // The debug route renders the same redacted text, which is what a debugger and
        // String(reflecting:) reach.
        XCTAssertEqual(value.description, value.debugDescription)
        XCTAssertEqual(value.description, String(reflecting: value))
    }

    func testUseDigitsRethrowsAndLeavesTheValueUntouched() {
        // A reader that keeps the digits it was lent keeps them alive; wiping what a reader kept is
        // the reader's work. What is asserted is the contract every reader relies on: the error is
        // rethrown and the value itself is untouched.
        let value = SensitiveDigits.ofString(pan)
        var lent: [UInt8]?

        XCTAssertThrowsError(try value.useDigits { digits in
            lent = digits
            throw Sentinel()
        })

        XCTAssertEqual(Array(pan.utf8), lent)
        XCTAssertEqual(Array(pan.utf8), value.read())
        XCTAssertFalse(value.isWiped)
        XCTAssertEqual(pan.count, value.length)
    }

    func testUseDigitsSeesTheDigitsAndLeavesTheValueUsable() {
        let value = SensitiveDigits.ofString(pan)
        var lent: [UInt8]?

        let length = value.useDigits { digits -> Int in
            lent = digits
            return digits.count
        }

        XCTAssertEqual(16, length)
        XCTAssertEqual(Array(pan.utf8), lent)
        // The value itself is untouched: lending the digits is not closing them.
        XCTAssertEqual(Array(pan.utf8), value.read())
        XCTAssertFalse(value.isWiped)
    }

    func testAnEmptyValueIsAllowedHereAndRefusedByValidation() {
        // Constructing one is not the place to reject it: a caller passing a blank field deserves a typed
        // validation failure naming the field, not an exception from a factory.
        let value = SensitiveDigits.ofString("")

        XCTAssertEqual(0, value.length)
    }
}
