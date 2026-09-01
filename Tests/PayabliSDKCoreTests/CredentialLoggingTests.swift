@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// What the credential-recovery path writes to the log, and what it must never write.
///
/// Driven over a real chain and a real holder, for the reason `AuthenticatedTransportTests` gives: a
/// double substituted for the service attaches no bearer, so a suite built on one cannot tell a working
/// chain from an absent one — and here the credential is the thing under test.
///
/// Every case anchors on a record it expects before asserting the credential is absent. Absence alone
/// passes on a path that stopped logging, and on a path that was never reached.
final class CredentialLoggingTests: XCTestCase {
    private static let unauthorized = 401
    private static let ok = 200

    /// Not a substring of any message asserted present below. A sentinel that appears inside an anchor
    /// makes its own absence assertion pass while carrying nothing.
    private static let refreshed = "SENTINEL-REFRESHED-CREDENTIAL"

    // MARK: - Across a refresh

    func testNeitherTheOldNorTheRefreshedTokenReachesTheLogAcrossARefresh() async throws {
        let stub = RecordingStub { request in
            bearer(of: request) == Self.refreshed ? (Self.ok, Data()) : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let sinks = LogSinks()
        let stack = try makeLoggingStack(tokenProvider: { Self.refreshed }, sinks: sinks)

        let response = try await stack.transport.perform(ping())

        // The refresh happened, so there was a credential to leak in the first place.
        XCTAssertEqual(response.statusCode, Self.ok)
        XCTAssertEqual(stub.sentTokens, [testToken, Self.refreshed])

        assertLogged("Access token refreshed", in: sinks.auth, category: .auth)
        assertLogged("credential rejected", in: sinks.network, category: .network)

        assertNeverLogged([testToken, Self.refreshed], in: sinks.all)
    }

    /// The rotation is the holder's to announce and the recovery is the transport's, so a reader looking
    /// for one under the other's category finds nothing. Without this, both records landing in one place
    /// would still satisfy the case above.
    func testTheRotationIsRecordedUnderAuthAndNotUnderNetwork() async throws {
        let stub = RecordingStub { request in
            bearer(of: request) == Self.refreshed ? (Self.ok, Data()) : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let sinks = LogSinks()
        let stack = try makeLoggingStack(tokenProvider: { Self.refreshed }, sinks: sinks)

        _ = try await stack.transport.perform(ping())

        assertLogged("Access token refreshed", in: sinks.auth, category: .auth)
        assertNotLogged("Access token refreshed", in: sinks.network, category: .network)
    }

    func testTheReplayIsRecordedSoARecoveryIsNotSilent() async throws {
        let stub = RecordingStub { request in
            bearer(of: request) == Self.refreshed ? (Self.ok, Data()) : (Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let sinks = LogSinks()
        let stack = try makeLoggingStack(tokenProvider: { Self.refreshed }, sinks: sinks)

        _ = try await stack.transport.perform(ping())

        assertLogged("replaying GET", in: sinks.network, category: .network)
        assertNeverLogged([testToken, Self.refreshed], in: sinks.all)
    }

    // MARK: - When recovery runs out

    func testAnExhaustedRecoverySaysWhyAndCarriesNoCredential() async throws {
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }

        let sinks = LogSinks()
        let stack = try makeLoggingStack(tokenProvider: { Self.refreshed }, sinks: sinks)

        do {
            _ = try await stack.transport.perform(ping())
            XCTFail("a second 401 is terminal")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.code, .tokenExpired)
        }

        assertLogged("recovery exhausted", in: sinks.network, category: .network)
        assertLogged("credential rejected", in: sinks.network, category: .network)

        assertNeverLogged([testToken, Self.refreshed], in: sinks.all)
    }

    /// A request that never sees a 401 writes no recovery record at all. This is what keeps the anchors
    /// above meaningful: they name a record the recovery path writes, not one every request writes.
    func testASuccessfulRequestRecordsNoRecovery() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        let sinks = LogSinks()
        let stack = try makeLoggingStack(sinks: sinks)

        _ = try await stack.transport.perform(ping())

        assertNotLogged("credential rejected", in: sinks.network, category: .network)
        assertNotLogged("recovery exhausted", in: sinks.network, category: .network)
        assertNeverLogged([testToken], in: sinks.all)
    }

    /// The no-provider path throws from the refresh and never replays, so the record written ahead of it
    /// must claim neither. Anchors on the attempt and asserts the replay record is absent.
    func testARejectionWithNoProviderRecordsTheAttemptAndNoReplay() async throws {
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }

        let sinks = LogSinks()
        let stack = try makeLoggingStack(sinks: sinks)

        do {
            _ = try await stack.transport.perform(ping())
            XCTFail("a 401 with no provider is terminal")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.code, .tokenExpired)
        }

        XCTAssertEqual(stub.count, 1, "nothing to refresh with, so nothing is replayed")
        assertLogged("attempting recovery", in: sinks.network, category: .network)
        assertNotLogged("replaying", in: sinks.network, category: .network)
        assertNeverLogged([testToken], in: sinks.all)
    }

    // MARK: - Helpers

    private func ping() -> PayabliRequest {
        PayabliRequest(method: .get, path: "/api/v2/ping")
    }
}

private func bearer(of request: URLRequest) -> String? {
    request.value(forHTTPHeaderField: "Authorization")?
        .replacingOccurrences(of: "Bearer ", with: "")
}
