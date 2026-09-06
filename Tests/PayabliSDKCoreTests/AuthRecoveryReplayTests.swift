@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// What a widened credential rejection may and may not replay, and that the transport asks the policy
/// instead of re-deriving the status itself.
///
/// Driven over a real chain, like the rest of the recovery suite: a double substituted for the service
/// attaches no bearer, so a suite built on one cannot tell a working chain from an absent one.
final class AuthRecoveryReplayTests: XCTestCase {
    private static let ok = 200
    private static let unauthorized = 401
    private let widened = WidenedRecoveryPolicy.widenedStatus

    // MARK: - A 401 replays whatever the method is

    func testA401OnPostRefreshesAndReplays() async throws {
        let outcome = try await run(method: .post, refusing: Self.unauthorized)

        XCTAssertEqual(outcome.refreshes, 1)
        XCTAssertEqual(outcome.sends, 2, "a 401 precedes processing, so replaying it cannot double-execute")
    }

    // MARK: - A widened rejection replays only an idempotent method

    func testAWidenedRejectionOnGetRefreshesAndReplays() async throws {
        let outcome = try await run(method: .get, refusing: widened, policy: WidenedRecoveryPolicy())

        XCTAssertEqual(outcome.refreshes, 1)
        XCTAssertEqual(outcome.sends, 2)
    }

    func testAWidenedRejectionOnPutRefreshesAndReplays() async throws {
        let outcome = try await run(method: .put, refusing: widened, policy: WidenedRecoveryPolicy())

        XCTAssertEqual(outcome.refreshes, 1)
        XCTAssertEqual(outcome.sends, 2)
    }

    func testAWidenedRejectionOnDeleteRefreshesAndReplays() async throws {
        let outcome = try await run(method: .delete, refusing: widened, policy: WidenedRecoveryPolicy())

        XCTAssertEqual(outcome.refreshes, 1)
        XCTAssertEqual(outcome.sends, 2)
    }

    func testAWidenedRejectionOnPostRefreshesButReturnsTheOriginalResponseWithoutReplay() async throws {
        let outcome = try await run(method: .post, refusing: widened, policy: WidenedRecoveryPolicy())

        XCTAssertEqual(outcome.refreshes, 1, "the credential is replaced so the next request starts clean")
        XCTAssertEqual(outcome.sends, 1, "nothing makes a second POST safe here")
        XCTAssertEqual(outcome.status, widened, "the rejection reaches the caller as it arrived")
    }

    func testAWidenedRejectionOnPatchRefreshesButReturnsTheOriginalResponseWithoutReplay() async throws {
        // PATCH specifically: it reads as a sibling of PUT and RFC 9110 does not make it idempotent.
        let outcome = try await run(method: .patch, refusing: widened, policy: WidenedRecoveryPolicy())

        XCTAssertEqual(outcome.refreshes, 1)
        XCTAssertEqual(outcome.sends, 1)
        XCTAssertEqual(outcome.status, widened)
    }

    // MARK: - The seam is a seam

    /// Fails if the transport goes back to comparing `statusCode == 401` itself, which is the difference
    /// between a seam and something that resembles one.
    func testTheMechanismObeysThePolicyRatherThanReDerivingTheStatus() async throws {
        let outcome = try await run(
            method: .get,
            refusing: Self.unauthorized,
            policy: RefusingRecoveryPolicy()
        )

        XCTAssertEqual(outcome.refreshes, 0, "the policy said this is not a credential rejection")
        XCTAssertEqual(outcome.sends, 1)
        XCTAssertEqual(outcome.status, Self.unauthorized, "and it reaches the caller untouched")
    }

    // MARK: - What the declined branch records

    func testADeclinedReplaySaysWhyWithoutTheTokenTheBodyOrTheResolvedPath() async throws {
        let sink = RecordingLogSink()
        let secret = Data(#"{"pan":"4111111111111111"}"#.utf8)

        _ = try await run(
            method: .post,
            refusing: widened,
            policy: WidenedRecoveryPolicy(),
            sink: sink,
            body: secret
        )

        // Presence first: a log writing nothing at all would satisfy every absence assertion below.
        let declined = try XCTUnwrap(
            sink.records.first { $0.message.contains("replay declined") },
            "the declined branch has to say it declined"
        )

        XCTAssertTrue(declined.message.contains("POST"), "and which method it refused to send again")
        XCTAssertTrue(declined.message.contains("\(widened)"), "and what the service answered")

        // Scoped to this record rather than the whole log: the transport below writes its own request
        // and response lines, and what they carry is that layer's question.
        XCTAssertFalse(declined.message.contains(testToken), "no credential")
        XCTAssertFalse(declined.message.contains("refreshed-token"), "not the new one either")
        XCTAssertFalse(declined.message.contains("4111"), "no body")
        XCTAssertFalse(declined.message.contains("/api/v2/"), "no resolved path")
    }

    // MARK: - Driver

    private struct Outcome {
        let status: Int
        let sends: Int
        let refreshes: Int
    }

    private func run(
        method: HTTPMethod,
        refusing refusalStatus: Int,
        policy: any AuthRecoveryPolicy = DefaultAuthRecoveryPolicy(),
        sink: RecordingLogSink? = nil,
        body: Data? = nil
    ) async throws -> Outcome {
        let provider = Counter()
        let stub = RecordingStub { request in
            bearerToken(of: request) == "refreshed-token"
                ? (Self.ok, Data())
                : (refusalStatus, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let auth = try makeTestAuth(tokenProvider: {
            _ = await provider.increment()
            return "refreshed-token"
        })
        let transport = makeAuthenticatedStack(auth: auth, recovery: policy, sink: sink)

        let request = PayabliRequest(method: method, path: "/api/v2/ping", body: body)
        let response = try await transport.perform(request)

        return Outcome(
            status: response.statusCode,
            sends: stub.count,
            refreshes: await provider.count
        )
    }
}

private func bearerToken(of request: URLRequest) -> String? {
    request.value(forHTTPHeaderField: "Authorization")?
        .replacingOccurrences(of: "Bearer ", with: "")
}
