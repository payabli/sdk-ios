@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// The credential-recovery layer, driven over a real chain.
///
/// Every case here runs `AuthenticatedTransport` over a `PayabliService` whose chain attaches the
/// bearer, which is the shape production runs. A double substituted for the service attaches nothing,
/// so a suite built on one cannot tell a working chain from an absent one.
final class AuthenticatedTransportTests: XCTestCase {
    private static let unauthorized = 401
    private static let ok = 200

    // MARK: - Bearer injection

    func testTheBearerIsOnEveryRequest() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth()
        let transport = makeAuthenticatedStack(auth: auth)

        for _ in 0 ..< 3 {
            _ = try await transport.perform(ping())
        }

        XCTAssertEqual(stub.sentTokens, [testToken, testToken, testToken])
    }

    // MARK: - 401 recovery

    func testOne401TriggersOneRefreshAndOneRetryCarryingTheNewToken() async throws {
        let provider = Counter()
        let stub = RecordingStub { request in
            bearer(of: request) == "refreshed-token"
                ? (Self.ok, Data())
                : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: {
            _ = await provider.increment()
            return "refreshed-token"
        })
        let transport = makeAuthenticatedStack(auth: auth)

        let response = try await transport.perform(ping())

        XCTAssertEqual(response.statusCode, Self.ok)
        let refreshes = await provider.count
        XCTAssertEqual(refreshes, 1, "one rejection is one refresh")
        XCTAssertEqual(stub.sentTokens, [testToken, "refreshed-token"])
    }

    func testASecond401IsTerminalAndThereIsNoThirdAttempt() async throws {
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: { "refreshed-token" })
        let transport = makeAuthenticatedStack(auth: auth)

        let failure = await failure(from: { _ = try await transport.perform(self.ping()) })

        XCTAssertEqual((failure as? PayabliGenericError)?.code, .tokenExpired)
        XCTAssertEqual(stub.count, 2, "no third attempt")
    }

    func testA401OnPostStillRefreshesAndReplays() async throws {
        let stub = RecordingStub { request in
            bearer(of: request) == "refreshed-token"
                ? (Self.ok, Data())
                : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: { "refreshed-token" })
        let transport = makeAuthenticatedStack(auth: auth)

        let response = try await transport.perform(
            PayabliRequest(method: .post, path: "/api/pay", body: Data("{}".utf8))
        )

        XCTAssertEqual(response.statusCode, Self.ok)
        XCTAssertEqual(stub.requests.map(\.httpMethod), ["POST", "POST"])
    }

    func testTheRetryReSendsTheBodyUnchanged() async throws {
        let body = Data(#"{"amount":100}"#.utf8)
        let stub = RecordingStub { request in
            bearer(of: request) == "refreshed-token"
                ? (Self.ok, Data())
                : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: { "refreshed-token" })
        let transport = makeAuthenticatedStack(auth: auth)

        _ = try await transport.perform(
            PayabliRequest(method: .post, path: "/api/pay", body: body)
        )

        XCTAssertEqual(stub.requests.count, 2)
        XCTAssertEqual(stub.requests.map(\.httpBody), [body, body])
    }

    // MARK: - Which token gets reported as refused

    /// A rotation landing between the recovery layer reading the token and the chain reading it again.
    ///
    /// The two reads are separate, so they can disagree. Reporting the remembered one sends the holder
    /// down its already-rotated branch, which hands back the token that was just refused without
    /// calling the provider, and the replay repeats it.
    ///
    /// A gate parks the request ahead of the bearer and the token is rotated while it is parked, so
    /// the timing is established.
    func testARotationBetweenTheTwoReadsStillRefreshesTheTokenThatWasActuallySent() async throws {
        let stub = RecordingStub { request in
            // Only the token minted for this caller is accepted, so a replay of anything else fails.
            bearer(of: request) == "minted-for-us" ? (Self.ok, Data()) : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let provider = Counter()
        let auth = try makeTestAuth(tokenProvider: {
            let call = await provider.increment()
            return call == 1 ? "rotated-by-other" : "minted-for-us"
        })
        let gate = GateDecoration()
        let transport = makeStackWithChain(
            [gate, BearerDecoration(readToken: { await auth.currentAccessToken() })],
            auth: auth
        )

        let caller = Task { try await transport.perform(self.ping()) }
        await gate.waitUntilParked()
        // Another caller rotates the token while this request is parked before the bearer is read.
        _ = try await auth.invalidateAndRefresh(rejectedToken: testToken)
        gate.release()

        let response = try await caller.value

        XCTAssertEqual(response.statusCode, Self.ok)
        let refreshes = await provider.count
        XCTAssertEqual(refreshes, 2, "the provider ran again for the token actually sent")
        XCTAssertEqual(
            stub.sentTokens.last,
            "minted-for-us",
            "the replay carried a freshly minted token, not the one just refused"
        )
    }

    // MARK: - Concurrency

    func testFiveCallersHoldingTheStaleTokenShareASingleRefresh() async throws {
        let provider = Counter()
        let stub = RecordingStub { request in
            bearer(of: request) == "refreshed-token"
                ? (Self.ok, Data())
                : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: {
            _ = await provider.increment()
            return "refreshed-token"
        })
        // Parked behind the bearer, so every caller has stamped the stale token before any of them is
        // refused. Without it the count below depends on which caller the scheduler runs first.
        let gate = GateDecoration()
        let transport = makeStackWithChain(
            [BearerDecoration(readToken: { await auth.currentAccessToken() }), gate],
            auth: auth
        )

        let callers = (0 ..< 5).map { _ in
            Task { try await transport.perform(self.ping()) }
        }
        await gate.waitUntilParked(count: 5)
        gate.release()

        var outcomes: [String] = []
        for caller in callers {
            do {
                outcomes.append("\(try await caller.value.statusCode)")
            } catch {
                outcomes.append("threw \(error)")
            }
        }

        let sent = stub.sentTokens
        // Every caller's outcome and the whole traffic, so a failure names which callers recovered.
        XCTAssertEqual(
            outcomes,
            Array(repeating: "\(Self.ok)", count: 5),
            "every caller recovered; traffic was \(sent)"
        )
        let refreshes = await provider.count
        XCTAssertEqual(refreshes, 1, "five rejections, one refresh; traffic was \(sent)")
        XCTAssertEqual(sent.filter { $0 == testToken }.count, 5, "traffic was \(sent)")
        XCTAssertEqual(sent.filter { $0 == "refreshed-token" }.count, 5, "traffic was \(sent)")
    }

    /// A provider that issues its own request through the SDK while its own refresh is in flight.
    ///
    /// The nested request carries the token being replaced, so it is refused; it completes on that
    /// refusal instead of joining the refresh that is waiting on the provider that issued it.
    ///
    /// Bounded, because the failure it covers is a wedge rather than a wrong answer. An unbounded wait
    /// hangs the suite, which prints no failure and reads exactly like passing.
    func testAProviderThatIssuesItsOwnRequestThroughTheSdkDoesNotDeadlock() async throws {
        let stub = RecordingStub { request in
            bearer(of: request) == "refreshed-token"
                ? (Self.ok, Data())
                : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let request = ping()
        let stack = Slot<any PayabliTransport>()
        let nested = Slot<String>()
        let providerCalls = Counter()

        let auth = try makeTestAuth(tokenProvider: {
            _ = await providerCalls.increment()
            // The host reaching for the SDK-shaped HTTP path it already has.
            do {
                let response = try await stack.value!.perform(request)
                nested.set("\(response.statusCode)")
            } catch let error as PayabliGenericError {
                nested.set(error.code.rawValue)
            }
            return "refreshed-token"
        })
        stack.set(makeAuthenticatedStack(auth: auth))

        let outcome = await outcomeWithinCeiling {
            do {
                return "\(try await stack.value!.perform(request).statusCode)"
            } catch let error as PayabliGenericError {
                return error.code.rawValue
            } catch {
                return "\(error)"
            }
        }

        guard let outcome else {
            return XCTFail(
                "the request never finished: the provider's own request joined the refresh awaiting it"
            )
        }
        XCTAssertEqual(outcome, "\(Self.ok)", "traffic was \(stub.sentTokens)")
        // Completing is the guarantee, not succeeding: the nested request could only carry the token
        // being replaced, so it is refused twice and reports the credential.
        XCTAssertEqual(
            nested.value,
            PayabliErrorCode.tokenExpired.rawValue,
            "traffic was \(stub.sentTokens)"
        )
        let refreshes = await providerCalls.count
        XCTAssertEqual(refreshes, 1, "the nested request must not start a second refresh")
    }

    // MARK: - The decoding overload

    func testTheDecodingOverloadRefreshesAndRetriesToo() async throws {
        let approved = Data(#"{"code":"A0000","reason":"Approved","data":{"paymentTransId":"txn-9"}}"#.utf8)
        let stub = RecordingStub { request in
            bearer(of: request) == "refreshed-token"
                ? (Self.ok, approved)
                : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: { "refreshed-token" })
        let transport = makeAuthenticatedStack(auth: auth)

        let envelope = try await transport.performV2(ping(), decoding: TransactionPayload.self)

        XCTAssertEqual(envelope.data?.paymentTransId, "txn-9")
        XCTAssertEqual(stub.sentTokens.last, "refreshed-token")
    }

    /// A decoded route ending in two 401s reports the credential, not the empty body it never got.
    func testADecodedRouteEndingInTwo401sReportsTokenExpiredNotADecodeFailure() async throws {
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: { "refreshed-token" })
        let transport = makeAuthenticatedStack(auth: auth)

        let failure = await failure(from: {
            _ = try await transport.performV2(self.ping(), decoding: TransactionPayload.self)
        })

        XCTAssertEqual((failure as? PayabliGenericError)?.code, .tokenExpired)
    }

    // MARK: - Terminal and pass-through cases

    func testA401WithNoProviderIsTerminalAndIsNotRetried() async throws {
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth()
        let transport = makeAuthenticatedStack(auth: auth)

        let failure = await failure(from: { _ = try await transport.perform(self.ping()) })

        XCTAssertEqual((failure as? PayabliGenericError)?.code, .tokenExpired)
        XCTAssertEqual(stub.count, 1, "nothing to refresh with, so nothing is replayed")
    }

    func testAFailingProviderIsTerminalNotRetriedAndDoesNotLeakItsOwnMessage() async throws {
        let sentinel = "SENTINEL-PROVIDER-DETAIL"
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: {
            throw NSError(domain: sentinel, code: 1, userInfo: [NSLocalizedDescriptionKey: sentinel])
        })
        let transport = makeAuthenticatedStack(auth: auth)

        let failure = await failure(from: { _ = try await transport.perform(self.ping()) })

        XCTAssertEqual((failure as? PayabliGenericError)?.code, .tokenExpired)
        XCTAssertEqual(stub.count, 1)
        XCTAssertFalse("\(failure)".contains(sentinel), "the host's own message is not ours to relay")
        XCTAssertFalse(
            failure.localizedDescription.contains(sentinel),
            "nor through the rendering a crash reporter reads"
        )
    }

    func testANon401FailureIsReturnedUntouchedAndTriggersNoRefresh() async throws {
        let provider = Counter()
        let stub = RecordingStub(status: 500)
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: {
            _ = await provider.increment()
            return "refreshed-token"
        })
        let transport = makeAuthenticatedStack(auth: auth)

        let response = try await transport.perform(ping())

        XCTAssertEqual(response.statusCode, 500, "a non-2xx response is not a failure to recover from")
        let refreshes = await provider.count
        XCTAssertEqual(refreshes, 0)
        XCTAssertEqual(stub.count, 1)
    }

    // MARK: - Helpers

    private func ping() -> PayabliRequest {
        PayabliRequest(method: .get, path: "/api/v2/ping")
    }

    /// Asserts the block threw, and returns what it threw. A success fails the test here, so the
    /// assertions below it are never quietly skipped.
    private func failure(
        from block: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> any Error {
        do {
            try await block()
            XCTFail("expected a failure, got a success", file: file, line: line)
            return PayabliGenericError(code: .unknown, reason: "no failure")
        } catch {
            return error
        }
    }
}

private func bearer(of request: URLRequest) -> String? {
    request.value(forHTTPHeaderField: "Authorization")?
        .replacingOccurrences(of: "Bearer ", with: "")
}

private struct TransactionPayload: Decodable, Sendable {
    let paymentTransId: String?
}
