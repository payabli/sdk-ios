@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// The transport obtained the way production obtains one carries a chain.
///
/// Asserted against the transport a caller can actually build, not a hand-assembled chain.
final class PayabliTransportTests: XCTestCase {
    func testTheProductionInitializerCarriesAChainThatAttachesTheBearer() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        let service = PayabliService(
            environment: .sandbox,
            readToken: { "tok-from-read" },
            session: StubURLProtocol.makeSession()
        )

        _ = try await service.perform(PayabliRequest(method: .get, path: "/api/v2/anything"))

        XCTAssertEqual(stub.count, 1)
        XCTAssertEqual(stub.sentTokens, ["tok-from-read"])
    }

    /// The credential is read per request, so a rotation needs no cache invalidated.
    func testEachRequestReadsTheTokenAgain() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        let minted = Counter()
        let service = PayabliService(
            environment: .sandbox,
            readToken: { "tok-\(await minted.increment())" },
            session: StubURLProtocol.makeSession()
        )

        for _ in 0 ..< 3 {
            _ = try await service.perform(PayabliRequest(method: .get, path: "/api/v2/anything"))
        }

        XCTAssertEqual(stub.sentTokens, ["tok-1", "tok-2", "tok-3"])
    }

    /// A read that fails stops the request, so nothing goes out unauthenticated.
    ///
    /// The chain runs before the request is built, which is what lets a surface put its own guard in
    /// the read and spend no round trip on a refused token.
    func testAFailingTokenReadStopsTheRequestBeforeItIsSent() async throws {
        struct NoToken: Error {}

        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        let service = PayabliService(
            environment: .sandbox,
            readToken: { throw NoToken() },
            session: StubURLProtocol.makeSession()
        )

        do {
            _ = try await service.perform(PayabliRequest(method: .get, path: "/api/v2/anything"))
            XCTFail("expected the read to refuse")
        } catch is NoToken {
            // The read's own error travels, so a surface can name the refusal in its own vocabulary.
        }

        XCTAssertEqual(stub.count, 0, "nothing was sent")
    }

    /// A body with no content type is labelled, because a request that reaches the service unlabelled
    /// is read as something other than JSON.
    func testABodyWithNoContentTypeIsLabelled() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        let service = PayabliService(
            environment: .sandbox,
            readToken: { "tok" },
            session: StubURLProtocol.makeSession()
        )

        _ = try await service.perform(PayabliRequest(
            method: .post,
            path: "/api/v2/anything",
            body: Data("{}".utf8)
        ))

        XCTAssertEqual(
            stub.requests.first?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }
}
