@testable import PayabliSDKCore
import XCTest

/// The sibling SDK has this parser and no test for it, so these are written rather than ported.
final class RetryAfterHeaderTests: XCTestCase {
    private func response(_ value: String?, status: Int = 429) -> PayabliResponse {
        PayabliResponse(
            statusCode: status,
            headers: value.map { [RetryAfterHeader.name: $0] } ?? [:],
            body: Data()
        )
    }

    // MARK: - Delay in seconds

    func testDeltaSecondsIsRead() {
        XCTAssertEqual(RetryAfterHeader.value(from: response("120")), 120)
    }

    func testZeroSecondsIsAWaitOfNoneRatherThanNoInstruction() {
        XCTAssertEqual(RetryAfterHeader.value(from: response("0")), 0)
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(RetryAfterHeader.value(from: response("  30  ")), 30)
    }

    func testANegativeDelayReadsAsNoInstruction() {
        // Not zero: a value the field cannot carry says nothing, and falling back to the computed
        // backoff is the honest answer.
        XCTAssertNil(RetryAfterHeader.value(from: response("-5")))
    }

    func testADigitRunTooLargeToHoldSaturatesRatherThanReadingAsAbsent() throws {
        // It is still an instruction to wait, and an extreme one, so it has to stay above any ceiling it
        // is compared against. Reading it as absent would retry in about a second.
        let raw = String(repeating: "9", count: 40)
        let value = try XCTUnwrap(RetryAfterHeader.value(from: response(raw)))
        XCTAssertEqual(value, .greatestFiniteMagnitude)
    }

    // MARK: - HTTP-date

    func testAnImfFixdateIsRead() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let later = "Tue, 14 Nov 2023 22:14:20 GMT" // now + 60s
        let parsed = try XCTUnwrap(RetryAfterHeader.value(from: response(later), now: now))
        XCTAssertEqual(parsed, 60, accuracy: 1)
    }

    func testTheTwoObsoleteDateFormatsAreAcceptedToo() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for raw in ["Tuesday, 14-Nov-23 22:14:20 GMT", "Tue Nov 14 22:14:20 2023"] {
            let parsed = try XCTUnwrap(RetryAfterHeader.value(from: response(raw), now: now))
            XCTAssertEqual(parsed, 60, accuracy: 1, "\(raw) must parse")
        }
    }

    func testADateAlreadyPastReadsAsNoWaitRatherThanANegativeOne() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier = "Tue, 14 Nov 2023 22:00:00 GMT"
        XCTAssertEqual(RetryAfterHeader.value(from: response(earlier), now: now), 0)
    }

    // MARK: - Absent and unreadable

    func testAnAbsentHeaderReadsAsNoInstruction() {
        XCTAssertNil(RetryAfterHeader.value(from: response(nil)))
    }

    func testAnEmptyHeaderReadsAsNoInstruction() {
        XCTAssertNil(RetryAfterHeader.value(from: response("   ")))
    }

    func testAnUnreadableValueReadsAsNoInstructionRatherThanFailing() {
        for raw in ["soon", "12 seconds", "Tue, 32 Nov 2023 22:00:00 GMT"] {
            XCTAssertNil(RetryAfterHeader.value(from: response(raw)), "\(raw) must not be read as a wait")
        }
    }

    // MARK: - Through the mapper

    // The parser and the retry engine are covered apart, and both stay green if the mapper drops the
    // parsed value on the floor: the engine's own cases construct their hints directly. These two run a
    // real response through `mapPayabliHTTPError` and read the hint off what it threw.

    func testA429CarriesItsParsedHintIntoTheThrownError() throws {
        let response = PayabliResponse(
            statusCode: 429,
            headers: [RetryAfterHeader.name: "90"],
            body: Data()
        )

        do {
            try mapPayabliHTTPError(response: response)
            XCTFail("a 429 has to map to an error")
        } catch let error as PayabliRateLimitError {
            XCTAssertEqual(error.retryAfter, 90)
        }
    }

    func testA5xxCarriesItsParsedHintAndItsStatusIntoTheThrownError() throws {
        let response = PayabliResponse(
            statusCode: 503,
            headers: [RetryAfterHeader.name: "30"],
            body: Data(#"{"title":"Service Unavailable"}"#.utf8)
        )

        do {
            try mapPayabliHTTPError(response: response)
            XCTFail("a 503 has to map to an error")
        } catch let PayabliPaymentError.server(server) {
            XCTAssertEqual(server.retryAfter, 30, "the hint has to survive decoding and the copy")
            XCTAssertEqual(server.httpStatus, 503)
        }
    }

    func testAStatusThatCarriesNoHintReportsNone() throws {
        // Only 429 and 5xx are given one, so a 403 with the field set still reports nothing: reading it
        // there would invent a wait the retry layer would then honour.
        let response = PayabliResponse(
            statusCode: 403,
            headers: [RetryAfterHeader.name: "90"],
            body: Data()
        )

        do {
            try mapPayabliHTTPError(response: response)
            XCTFail("a 403 has to map to an error")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.code, .permissionDenied)
            XCTAssertNil(error as? any PayabliRetryAfter, "a 403 carries no hint")
        }
    }

    // MARK: - Case

    func testALowercasedFieldNameIsFoundToo() {
        // HTTP/2 lower-cases every field name on the wire, so this is the ordinary case rather than an
        // edge one. Subscripting the dictionary would miss it.
        let lowercased = PayabliResponse(statusCode: 429, headers: ["retry-after": "45"], body: Data())
        XCTAssertEqual(RetryAfterHeader.value(from: lowercased), 45)
    }
}
