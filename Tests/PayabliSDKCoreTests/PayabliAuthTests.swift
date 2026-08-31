import PayabliSDKCore
import XCTest

final class PayabliAuthTests: XCTestCase {
    // MARK: - Helpers

    private func makeConfig(
        accessToken: String = "partner_minted_token",
        tokenProvider: PayabliTokenRefresh? = nil
    ) throws -> PayabliConfig {
        try PayabliConfig(
            accessToken: accessToken,
            tokenProvider: tokenProvider,
            entryPoint: "test_entry",
            environment: .sandbox
        )
    }

    // MARK: - Initial token

    func testInitialTokenComesFromConfig() async throws {
        let auth = PayabliAuth(config: try makeConfig(accessToken: "seed"))
        let token = await auth.currentAccessToken()
        XCTAssertEqual(token, "seed")
    }

    // MARK: - Refresh via tokenProvider

    func testInvalidateAndRefreshCallsProvider() async throws {
        let counter = Counter()
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                await counter.increment()
                return "fresh_from_partner"
            }
        ))

        let fresh = try await auth.invalidateAndRefresh(rejectedToken: "old")
        XCTAssertEqual(fresh, "fresh_from_partner")
        let calls = await counter.value
        XCTAssertEqual(calls, 1)

        // Subsequent currentAccessToken returns the refreshed value.
        let current = await auth.currentAccessToken()
        XCTAssertEqual(current, "fresh_from_partner")
    }

    func testInvalidateAndRefreshWithoutProviderThrowsTokenExpired() async throws {
        let auth = PayabliAuth(config: try makeConfig(accessToken: "old", tokenProvider: nil))
        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testInvalidateAndRefreshCoalescesConcurrentCallers() async throws {
        let counter = Counter()
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                await counter.increment()
                try await Task.sleep(nanoseconds: 20_000_000)
                return "fresh"
            }
        ))

        async let a = auth.invalidateAndRefresh(rejectedToken: "old")
        async let b = auth.invalidateAndRefresh(rejectedToken: "old")
        async let c = auth.invalidateAndRefresh(rejectedToken: "old")
        let results = try await [a, b, c]

        XCTAssertEqual(Set(results), ["fresh"])
        let calls = await counter.value
        XCTAssertEqual(calls, 1, "Concurrent refresh requests should share a single in-flight Task")
    }

    func testProviderErrorMapsToTokenExpired() async throws {
        struct ProviderError: Error {}
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: { throw ProviderError() }
        ))
        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - The rejected token

    /// Two requests sent with the same token can have their 401s arrive far apart.
    /// The later one must not spend a provider call replacing a token that has
    /// already rotated, which would discard the rotation the first one obtained.
    func testARejectionOnAnAlreadyRotatedTokenDoesNotCallTheProvider() async throws {
        let counter = Counter()
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                await counter.increment()
                return "fresh"
            }
        ))

        let first = try await auth.invalidateAndRefresh(rejectedToken: "old")
        XCTAssertEqual(first, "fresh")

        let second = try await auth.invalidateAndRefresh(rejectedToken: "old")
        XCTAssertEqual(second, "fresh", "The stale 401 should be answered with the rotated token")

        let calls = await counter.value
        XCTAssertEqual(calls, 1, "The second rejection names a token that is no longer current")
    }

    // MARK: - What may be committed

    func testAProviderReturningTheRejectedTokenFailsRatherThanLooping() async throws {
        let counter = Counter()
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: {
                await counter.increment()
                return "old"
            }
        ))

        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
        }

        let calls = await counter.value
        XCTAssertEqual(calls, 1)
        let current = await auth.currentAccessToken()
        XCTAssertEqual(current, "old", "The refused credential must not be committed")
    }

    func testABlankRefreshedTokenIsNotCommitted() async throws {
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: { "" }
        ))

        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
        }

        let current = await auth.currentAccessToken()
        XCTAssertEqual(current, "old")
    }

    /// A CR or LF in a bearer is header injection, and the platform drops the header
    /// rather than reporting it, so the request goes out unauthenticated.
    func testATokenThatCannotBeAHeaderValueIsNotCommitted() async throws {
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: { "fresh\r\nX-Injected: true" }
        ))

        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenMalformed)
        }

        let current = await auth.currentAccessToken()
        XCTAssertEqual(current, "old")
    }

    func testARefusedTokenPublishesNoRotation() async throws {
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: { "old" }
        ))

        let stream = await auth.tokenChanges()
        let collector = Task<String?, Never> {
            for await token in stream {
                return token
            }
            return nil
        }

        _ = try? await auth.invalidateAndRefresh(rejectedToken: "old")
        collector.cancel()
        let received = await collector.value
        XCTAssertNil(received, "A rotation that did not happen must not be announced")
    }

    // MARK: - What the provider's failure may carry

    /// The provider is host code and its error text can name the host's own endpoint
    /// or quote a response body. An `underlying` error reaches a crash reporter the
    /// SDK does not scrub.
    func testTheProvidersOwnMessageDoesNotReachTheErrorChain() async throws {
        // A stored property, because that is what a rendered error shows. A type
        // with none renders as its own name whatever `errorDescription` returns,
        // which would make this assertion unable to fail.
        struct ChattyProviderError: Error {
            let responseBody: String
        }
        let auth = PayabliAuth(config: try makeConfig(
            accessToken: "old",
            tokenProvider: { throw ChattyProviderError(responseBody: "SHOULD_NOT_LEAVE_THE_PROVIDER") }
        ))

        do {
            _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
            let rendered = "\(err) \(err.localizedDescription) \(String(describing: err.underlying))"
            XCTAssertFalse(
                rendered.contains("SHOULD_NOT_LEAVE_THE_PROVIDER"),
                "the provider's own text reached the error chain: \(rendered)"
            )
            XCTAssertTrue(
                rendered.contains("ChattyProviderError"),
                "the failing type should survive, since it names no subject: \(rendered)"
            )
        }
    }

    func testTokenChangesEmitsAfterRefresh() async throws {
        let config = try PayabliConfig(
            accessToken: "old",
            tokenProvider: { "new" },
            entryPoint: "demo",
            environment: .sandbox
        )
        let auth = PayabliAuth(config: config)

        let stream = await auth.tokenChanges()
        let collector = Task<String?, Never> {
            for await token in stream {
                return token
            }
            return nil
        }

        _ = try await auth.invalidateAndRefresh(rejectedToken: "old")
        let received = await collector.value
        XCTAssertEqual(received, "new")
    }
}

/// Simple actor counter for tracking concurrent calls in tests.
private actor Counter {
    private(set) var value: Int = 0
    func increment() {
        value += 1
    }
}
