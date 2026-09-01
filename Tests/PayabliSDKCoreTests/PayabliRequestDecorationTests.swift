@testable import PayabliSDKCore
import XCTest

/// The chain primitive: ordering, what a step may change, and who wins a header.
final class PayabliRequestDecorationTests: XCTestCase {
    private let request = PayabliRequest(
        method: .post,
        path: "/api/pay/9f3c1d",
        query: [URLQueryItem(name: "achValidation", value: "true")],
        headers: ["X-Caller": "kept"],
        body: Data(#"{"amount":100}"#.utf8)
    )

    // MARK: - Ordering

    func testStepsRunLeftToRightAndALaterStepSeesAnEarlierOnesOutput() async throws {
        let first = RecordingDecoration(stamp: ["X-First": "1"])
        let second = RecordingDecoration(stamp: ["X-Second": "2"])
        let chain: [any PayabliRequestDecoration] = [first, second]

        let decorated = try await chain.applyTo(request)

        XCTAssertNil(first.observed.first?.headers["X-First"], "index 0 ran first")
        XCTAssertEqual(second.observed.first?.headers["X-First"], "1", "the later step saw it")
        XCTAssertEqual(decorated.headers["X-First"], "1")
        XCTAssertEqual(decorated.headers["X-Second"], "2")
    }

    func testTheFactoryPutsContributorsInTheOrderTheChainDependsOn() {
        let chain = RequestDecorationFactory.chain(readToken: { "tok" })

        // A step that signs over what the others emit has to come after them, so the position of what
        // exists today is part of the contract.
        XCTAssertEqual(chain.count, 2)
        XCTAssertTrue(chain[0] is BearerDecoration)
        XCTAssertTrue(chain[1] is JSONBodyDecoration)
    }

    // MARK: - Who wins a header

    func testADecorationOverridesACallerHeaderOfTheSameName() async throws {
        let carrying = PayabliRequest(
            method: .get,
            path: "/api/v2/ping",
            headers: ["Authorization": "Bearer caller"]
        )

        let decorated = try await BearerDecoration(readToken: { "chain" }).decorate(carrying)

        XCTAssertEqual(decorated.headers["Authorization"], "Bearer chain")
    }

    /// Swift dictionaries are case-sensitive where header field names are not, so a differently-cased
    /// caller key left in place is a second `Authorization` heading for the wire with nothing deciding
    /// which value wins.
    func testADifferentlyCasedCallerHeaderIsRemovedNotShadowed() async throws {
        let carrying = PayabliRequest(
            method: .get,
            path: "/api/v2/ping",
            headers: ["authorization": "Bearer caller", "AUTHORIZATION": "Bearer also-caller"]
        )

        let decorated = try await BearerDecoration(readToken: { "chain" }).decorate(carrying)

        XCTAssertEqual(decorated.headers, ["Authorization": "Bearer chain"])
    }

    // MARK: - What a step may change

    /// A decoration changes headers and body. Everything else goes through one rebuild, so a property
    /// added to the request type reaches every step.
    func testIdentityFieldsAreCarriedThroughUntouched() async throws {
        let decorated = try await RecordingDecoration(stamp: ["X-Added": "1"]).decorate(request)

        XCTAssertEqual(decorated.method, request.method)
        XCTAssertEqual(decorated.path, request.path)
        XCTAssertEqual(decorated.query, request.query)
        XCTAssertEqual(decorated.body, request.body)
        XCTAssertEqual(decorated.headers["X-Caller"], "kept", "an unrelated caller header survives")
    }

    func testWithBodyReplacesTheBodyAndNothingElse() {
        let replaced = request.withBody(Data("{}".utf8))

        XCTAssertEqual(replaced.body, Data("{}".utf8))
        XCTAssertEqual(replaced.headers, request.headers)
        XCTAssertEqual(replaced.path, request.path)
    }

    // MARK: - The content-type default

    func testABodyWithNoContentTypeIsLabelled() async throws {
        let decorated = try await JSONBodyDecoration().decorate(request)

        XCTAssertEqual(decorated.headers[PayabliRequest.contentTypeHeader], "application/json")
    }

    func testItStepsAsideWhenTheCallerAlreadyNamedOneInAnyCase() async throws {
        let labelled = PayabliRequest(
            method: .post,
            path: "/api/pay",
            headers: ["content-type": "application/x-ndjson"],
            body: Data("{}".utf8)
        )

        let decorated = try await JSONBodyDecoration().decorate(labelled)

        XCTAssertEqual(decorated.headers, ["content-type": "application/x-ndjson"])
    }

    func testABodylessRequestIsNotLabelled() async throws {
        let bodyless = PayabliRequest(method: .get, path: "/api/v2/ping")

        let decorated = try await JSONBodyDecoration().decorate(bodyless)

        XCTAssertNil(decorated.headers[PayabliRequest.contentTypeHeader])
    }

    // MARK: - The sent-token record

    func testTheBearerRecordsWhatItStampedWhenABoxIsBound() async throws {
        let box = SentToken()

        try await SentToken.$current.withValue(box) {
            _ = try await BearerDecoration(readToken: { "stamped-token" }).decorate(request)
        }

        XCTAssertEqual(box.value, "stamped-token")
    }

    /// No box bound is legal and records nothing, which is what lets a transport with no recovery
    /// layer above it use the same chain.
    func testNoBoxBoundIsLegalAndRecordsNothing() async throws {
        let decorated = try await BearerDecoration(readToken: { "stamped-token" }).decorate(request)

        XCTAssertEqual(decorated.headers["Authorization"], "Bearer stamped-token")
        XCTAssertNil(SentToken.current)
    }
}
