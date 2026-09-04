import PayabliSDKCore
import XCTest

final class PayabliResponseTests: XCTestCase {
    func testHeaderLookupIgnoresCase() {
        let response = PayabliResponse(
            statusCode: 200,
            headers: ["content-type": "application/json"],
            body: Data()
        )
        XCTAssertEqual(response.header("Content-Type"), "application/json")
        XCTAssertEqual(response.header("CONTENT-TYPE"), "application/json")
        XCTAssertEqual(response.header("content-type"), "application/json")
    }

    func testHeaderLookupAnswersNilForAFieldThatIsNotThere() {
        let response = PayabliResponse(statusCode: 200, headers: [:], body: Data())
        XCTAssertNil(response.header("Retry-After"))
    }

    func testTheStoredKeysAreLeftAsTheSenderSpelledThem() {
        // The insensitivity belongs to the lookup. Rewriting the keys would change what a diagnostic and
        // a fixture show in order to solve a lookup problem.
        let response = PayabliResponse(statusCode: 200, headers: ["ReTrY-AfTeR": "1"], body: Data())
        XCTAssertEqual(Array(response.headers.keys), ["ReTrY-AfTeR"])
    }

    func testIsSuccessfulCoversTwoHundredsOnly() {
        for status in [200, 201, 204, 299] {
            XCTAssertTrue(PayabliResponse(statusCode: status, headers: [:], body: Data()).isSuccessful)
        }
        for status in [199, 300, 400, 401, 500] {
            XCTAssertFalse(PayabliResponse(statusCode: status, headers: [:], body: Data()).isSuccessful)
        }
    }

    func testBodyAsTextDecodesUTF8() {
        let response = PayabliResponse(
            statusCode: 200,
            headers: [:],
            body: Data("hello".utf8)
        )
        XCTAssertEqual(response.bodyAsText(), "hello")
    }

    func testBodyAsTextAnswersEmptyForBytesThatAreNotUTF8() {
        let response = PayabliResponse(statusCode: 200, headers: [:], body: Data([0xFF, 0xFE]))
        XCTAssertEqual(response.bodyAsText(), "")
    }

    /// The description reaches an assertion failure and a crash report without passing the logger, so it
    /// carries neither the body nor the headers. A synthesized one would print both.
    func testTheDescriptionCarriesNeitherTheBodyNorTheHeaders() {
        let response = PayabliResponse(
            statusCode: 500,
            headers: ["Authorization": "Bearer sensitive-token"],
            body: Data(#"{"pan":"4111111111111111"}"#.utf8)
        )

        let rendered = "\(response)"

        XCTAssertTrue(rendered.contains("500"))
        XCTAssertTrue(rendered.contains("bodyBytes"))
        XCTAssertFalse(rendered.contains("4111"))
        XCTAssertFalse(rendered.contains("sensitive-token"))
        XCTAssertFalse(rendered.contains("Authorization"))
    }

    func testTheDescriptionIsWhatStringDescribingUses() {
        let response = PayabliResponse(
            statusCode: 200,
            headers: ["X-Secret": "value"],
            body: Data("body".utf8)
        )
        XCTAssertFalse(String(describing: response).contains("X-Secret"))
    }
}
