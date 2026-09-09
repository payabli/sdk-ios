@testable import PayabliSDKCore
import XCTest

final class PercentEncodingTests: XCTestCase {
    func testTheUnreservedSetIsLeftAlone() {
        let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        XCTAssertEqual(PercentEncoding.segment(unreserved), unreserved)
    }

    /// The three that change what a request is rather than what it carries: another route, a query,
    /// a fragment.
    func testTheCharactersThatWouldReshapeTheRequestAreEncoded() {
        XCTAssertEqual(PercentEncoding.segment("a/b"), "a%2Fb")
        XCTAssertEqual(PercentEncoding.segment("a?b"), "a%3Fb")
        XCTAssertEqual(PercentEncoding.segment("a#b"), "a%23b")
    }

    /// `urlPathAllowed` admits these, so the previous encoder passed them through. A route is free
    /// to give any of them meaning, and the sibling platform encodes them.
    func testTheSubDelimitersAreEncoded() {
        XCTAssertEqual(PercentEncoding.segment("a;b"), "a%3Bb")
        XCTAssertEqual(PercentEncoding.segment("a=b"), "a%3Db")
        XCTAssertEqual(PercentEncoding.segment("a&b"), "a%26b")
        XCTAssertEqual(PercentEncoding.segment("a+b"), "a%2Bb")
        XCTAssertEqual(PercentEncoding.segment("a,b"), "a%2Cb")
        XCTAssertEqual(PercentEncoding.segment("a:b"), "a%3Ab")
        XCTAssertEqual(PercentEncoding.segment("a@b"), "a%40b")
    }

    /// A space is `%20` and never `+`: form encoding is a different thing that happens to look
    /// close, and a route reading `+` as a space is not something this can assume.
    func testASpaceIsEncodedAsAHexEscape() {
        XCTAssertEqual(PercentEncoding.segment("a b"), "a%20b")
    }

    /// Encoded from the UTF-8 bytes, so one character becomes as many escapes as it has bytes.
    func testAMultiByteCharacterIsEncodedPerByte() {
        XCTAssertEqual(PercentEncoding.segment("é"), "%C3%A9")
        XCTAssertEqual(PercentEncoding.segment("日"), "%E6%97%A5")
    }

    /// RFC 3986 Section 6.2.2.1: a producer writes the digits in upper case. Lower case would be
    /// equivalent to a reader and would not match the sibling byte for byte.
    func testTheHexadecimalDigitsAreUpperCase() {
        XCTAssertEqual(PercentEncoding.segment("\u{7F}"), "%7F")
        XCTAssertEqual(PercentEncoding.segment("~\u{1F}"), "~%1F")
    }

    /// Whether an empty value is acceptable is the caller's question. This records that the answer
    /// here is an empty segment rather than a refusal, because the difference is a different route.
    func testAnEmptyValueEncodesToAnEmptyString() {
        XCTAssertEqual(PercentEncoding.segment(""), "")
    }

    /// A value that is already encoded is encoded again, so a caller passes the raw identifier.
    func testAPercentIsItselfEncoded() {
        XCTAssertEqual(PercentEncoding.segment("a%2Fb"), "a%252Fb")
    }
}
