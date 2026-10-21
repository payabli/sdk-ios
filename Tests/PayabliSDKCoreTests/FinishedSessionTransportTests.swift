@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// A replay refused in turn finishes the session, and a finished session refuses every later request before it is sent.
/// A refusal of a token already replaced finishes nothing, and neither does a 401 on a route that pins its credential.
final class FinishedSessionTransportTests: XCTestCase {
    private static let unauthorized = 401
    private static let ok = 200

    func testARequestAfterARefusedReplayFailsWithoutARoundTripOrAProviderCall() async throws {
        let provider = Counter()
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: {
            _ = await provider.increment()
            return "refreshed-token"
        })
        let transport = makeAuthenticatedStack(auth: auth)
        _ = await failure(from: { _ = try await transport.perform(self.ping()) })
        let refreshesBefore = await provider.count

        let failure = await failure(from: { _ = try await transport.perform(self.ping()) })

        XCTAssertEqual((failure as? PayabliGenericError)?.type, .tokenExpired)
        XCTAssertEqual(stub.count, 2, "the second request never left")
        let refreshesAfter = await provider.count
        XCTAssertEqual(refreshesAfter, refreshesBefore, "and asked the provider for nothing")
    }

    func testARefusedReplayOfATokenAlreadyReplacedFailsItsCallerAndLeavesTheSessionUsable() async throws {
        let stub = RecordingStub { request in
            bearer(of: request) == "replaced-by-other" ? (Self.ok, Data()) : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let provider = Counter()
        let auth = try makeTestAuth(tokenProvider: {
            let call = await provider.increment()
            return call == 1 ? "minted-for-replay" : "replaced-by-other"
        })
        let gate = ParkSecondArrival()
        let transport = makeStackWithChain(
            [BearerDecoration(readToken: { try await auth.currentAccessToken() }), gate],
            auth: auth
        )

        let caller = Task { try await transport.perform(self.ping()) }
        await gate.waitUntilParked()
        // Another caller replaces the token while the replay carrying it is on its way.
        _ = try await auth.invalidateAndRefresh(rejectedToken: "minted-for-replay")
        gate.release()

        let failure = await failure(from: { _ = try await caller.value })
        XCTAssertEqual((failure as? PayabliGenericError)?.type, .tokenExpired, "the caller's own replay failed")

        let next = try await transport.perform(ping())
        XCTAssertEqual(next.statusCode, Self.ok, "the session was not finished by a refusal of a replaced token")
        XCTAssertEqual(stub.sentTokens.last, "replaced-by-other")
    }

    func testA401TheRequestNamesAsARefusalOfTheCallerIsReturnedWithoutRefreshOrReplay() async throws {
        let provider = Counter()
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: {
            _ = await provider.increment()
            return "refreshed-token"
        })
        let transport = makeAuthenticatedStack(auth: auth)
        let request = PayabliRequest(
            method: .get,
            path: "/api/v2/ping",
            isCallerRefusal: { $0.statusCode == Self.unauthorized }
        )

        let response = try await transport.perform(request)

        XCTAssertEqual(response.statusCode, Self.unauthorized)
        XCTAssertEqual(stub.count, 1, "no replay")
        let refreshes = await provider.count
        XCTAssertEqual(refreshes, 0, "no refresh")
    }

    func testA401OnAPinnedRouteNeverFinishesTheSession() async throws {
        let stub = RecordingStub { request in
            request.url?.path == "/api/v2/ping" ? (Self.ok, Data()) : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }
        let auth = try makeTestAuth(tokenProvider: { "refreshed-token" })
        let transport = makeAuthenticatedStack(auth: auth)
        let pinned = PayabliRequest(method: .get, path: "/api/v2/device/taptopay/config/entry", pinsCredential: true)

        _ = try await transport.perform(pinned)
        _ = try await transport.perform(pinned)
        let next = try await transport.perform(ping())

        XCTAssertNil(auth.terminalFailure, "a pinned refusal is renewed by the caller, never by finishing the session")
        XCTAssertEqual(next.statusCode, Self.ok)
    }

    func testRenewingOnAFinishedSessionReportsTheFinishAndAsksTheProviderForNothing() async throws {
        let provider = Counter()
        let auth = try makeTestAuth(tokenProvider: {
            _ = await provider.increment()
            return "would-be-renewed"
        })
        let held = try await auth.currentAccessToken()
        await auth.recordPinnedRefusal(of: held)
        await auth.finish(with: PayabliGenericError(type: .tokenExpired, reason: "finished"))

        let failure = await failure { _ = try await auth.renewPinnedRefusal() }

        XCTAssertEqual((failure as? PayabliGenericError)?.type, .tokenExpired)
        let calls = await provider.count
        XCTAssertEqual(calls, 0)
    }

    private func ping() -> PayabliRequest {
        PayabliRequest(method: .get, path: "/api/v2/ping")
    }

    /// Asserts the block threw, and returns what it threw. A success fails the test here, so the assertions after it
    /// are never quietly skipped.
    private func failure(
        from block: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> any Error {
        do {
            try await block()
            XCTFail("expected a failure, got a success", file: file, line: line)
            return PayabliGenericError(type: .unknown, reason: "no failure")
        } catch {
            return error
        }
    }
}

private func bearer(of request: URLRequest) -> String? {
    request.value(forHTTPHeaderField: "Authorization")?
        .replacingOccurrences(of: "Bearer ", with: "")
}

/// Parks the second request through the chain, which in a recovery is the replay, after its bearer is stamped.
private final class ParkSecondArrival: PayabliRequestDecoration, @unchecked Sendable {
    private let lock = NSLock()
    private var arrivals = 0
    private var parked: CheckedContinuation<Void, Never>?
    private var released = false

    func waitUntilParked(file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0 ..< 200 {
            if lock.withLock({ parked != nil }) {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        release()
        XCTFail("the replay never reached the gate", file: file, line: line)
    }

    func release() {
        let waiting = lock.withLock {
            released = true
            defer { parked = nil }
            return parked
        }
        waiting?.resume()
    }

    func decorate(_ request: PayabliRequest) async throws -> PayabliRequest {
        await withCheckedContinuation { continuation in
            lock.lock()
            arrivals += 1
            if arrivals == 2, !released {
                parked = continuation
                lock.unlock()
                return
            }
            lock.unlock()
            continuation.resume()
        }
        return request
    }
}
