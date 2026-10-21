@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// A route that pins its credential: a rejection comes back as it arrived, and the refused token waits to be renewed
/// between the calls of the sequence it belongs to.
final class PinnedCredentialTests: XCTestCase {
    private static let unauthorized = 401
    private static let ok = 200

    // MARK: - The transport

    func testA401OnAPinnedRouteNeitherRefreshesNorReplays() async throws {
        let provider = Counter()
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }
        let auth = try makeTestAuth(tokenProvider: {
            _ = await provider.increment()
            return "refreshed-token"
        })
        let transport = makeAuthenticatedStack(auth: auth)

        let response = try await transport.perform(pinned(.get))

        XCTAssertEqual(response.statusCode, Self.unauthorized, "the rejection reaches the caller as it arrived")
        XCTAssertEqual(stub.count, 1, "no replay")
        let refreshes = await provider.count
        XCTAssertEqual(refreshes, 0, "no refresh")
    }

    func testAPinnedPostIsNotReplayedEitherThoughA401WouldAllowIt() async throws {
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }
        let auth = try makeTestAuth(tokenProvider: { "refreshed-token" })
        let transport = makeAuthenticatedStack(auth: auth)

        let response = try await transport.perform(pinned(.post))

        XCTAssertEqual(response.statusCode, Self.unauthorized)
        XCTAssertEqual(stub.count, 1)
    }

    func testPinningOneRequestLeavesTheNextOneRecoveringNormally() async throws {
        let stub = RecordingStub { request in
            bearer(of: request) == "refreshed-token" ? (Self.ok, Data()) : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }
        let auth = try makeTestAuth(tokenProvider: { "refreshed-token" })
        let transport = makeAuthenticatedStack(auth: auth)

        _ = try await transport.perform(pinned(.get))
        let unpinned = try await transport.perform(PayabliRequest(method: .get, path: "/api/v2/ping"))

        XCTAssertEqual(unpinned.statusCode, Self.ok, "the unpinned request refreshed and replayed")
        XCTAssertEqual(stub.sentTokens, [testToken, testToken, "refreshed-token"])
    }

    func testThePinSurvivesTheDecorationCopy() async throws {
        let decorated = try await BearerDecoration(readToken: { "chain" }).decorate(pinned(.get))

        XCTAssertTrue(decorated.pinsCredential)
    }

    // MARK: - Renewing what a pinned route refused

    func testRenewingAfterAPinnedRefusalPutsANewTokenOnTheNextPinnedRequest() async throws {
        let stub = RecordingStub { request in
            bearer(of: request) == "renewed-token" ? (Self.ok, Data()) : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }
        let session = try makeSession(tokenProvider: { "renewed-token" })

        _ = try await session.transport.perform(pinned(.get))
        let renewed = try await session.renewRefusedToken()
        let next = try await session.transport.perform(pinned(.get))

        XCTAssertTrue(renewed)
        XCTAssertEqual(next.statusCode, Self.ok)
        XCTAssertEqual(stub.sentTokens, [testToken, "renewed-token"])
    }

    func testRenewingWithNoPinnedRefusalAsksTheProviderForNothing() async throws {
        let provider = Counter()
        let session = try makeSession(tokenProvider: {
            _ = await provider.increment()
            return "renewed-token"
        })

        let renewed = try await session.renewRefusedToken()

        XCTAssertFalse(renewed)
        let calls = await provider.count
        XCTAssertEqual(calls, 0)
    }

    func testRenewingAPinnedRefusalKeepsATokenAnotherRequestHasAlreadyRotated() async throws {
        let provider = Counter()
        let auth = try makeTestAuth(tokenProvider: {
            _ = await provider.increment()
            return "rotated-by-other"
        })
        let held = try await auth.currentAccessToken()
        await auth.recordPinnedRefusal(of: held)
        _ = try await auth.invalidateAndRefresh(rejectedToken: held)

        let renewed = try await auth.renewPinnedRefusal()

        XCTAssertTrue(renewed)
        let calls = await provider.count
        XCTAssertEqual(calls, 1, "the token had already moved on, so the renewal kept it")
        let current = try await auth.currentAccessToken()
        XCTAssertEqual(current, "rotated-by-other")
    }

    func testALateRefusalOfAReplacedTokenIsNotKept() async throws {
        let provider = Counter()
        let auth = try makeTestAuth(tokenProvider: {
            _ = await provider.increment()
            return "rotated-by-other"
        })
        let held = try await auth.currentAccessToken()
        _ = try await auth.invalidateAndRefresh(rejectedToken: held)

        await auth.recordPinnedRefusal(of: held)
        let renewed = try await auth.renewPinnedRefusal()

        XCTAssertFalse(renewed, "the refused token was no longer held, so nothing waited to be renewed")
        let calls = await provider.count
        XCTAssertEqual(calls, 1)
    }

    // MARK: - Helpers

    private func pinned(_ method: HTTPMethod) -> PayabliRequest {
        PayabliRequest(method: method, path: "/api/v2/device/taptopay/config/entry", pinsCredential: true)
    }

    /// A session on the stubbed network whose first token is `testToken` and whose provider serves every call after.
    private func makeSession(tokenProvider: @escaping PayabliTokenRefresh) throws -> PayabliSession {
        let calls = Counter()
        let config = try PayabliConfig(
            entryPoint: "entry",
            environment: .sandbox,
            tokenProvider: {
                let call = await calls.increment()
                return call == 1 ? testToken : try await tokenProvider()
            }
        )
        return PayabliSession(config: config, urlSession: StubURLProtocol.makeSession())
    }
}

private func bearer(of request: URLRequest) -> String? {
    request.value(forHTTPHeaderField: "Authorization")?
        .replacingOccurrences(of: "Bearer ", with: "")
}
