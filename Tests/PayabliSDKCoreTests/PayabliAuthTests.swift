import XCTest
@testable import PayabliSDKCore

final class PayabliAuthTests: XCTestCase {

    // MARK: - Helpers

    private func makeConfig(
        accessToken: String = "partner_minted_token",
        tokenProvider: PayabliTokenRefresh? = nil
    ) -> PayabliConfig {
        PayabliConfig(
            accessToken: accessToken,
            tokenProvider: tokenProvider,
            entryPoint: "test_entry",
            environment: .sandbox
        )
    }

    // MARK: - Initial token

    func testInitialTokenComesFromConfig() async throws {
        let auth = PayabliAuth(config: makeConfig(accessToken: "seed"))
        let token = await auth.currentAccessToken()
        XCTAssertEqual(token, "seed")
    }

    // MARK: - Refresh via tokenProvider

    func testInvalidateAndRefreshCallsProvider() async throws {
        let counter = Counter()
        let auth = PayabliAuth(config: makeConfig(
            accessToken: "old",
            tokenProvider: {
                await counter.increment()
                return "fresh_from_partner"
            }
        ))

        let fresh = try await auth.invalidateAndRefresh()
        XCTAssertEqual(fresh, "fresh_from_partner")
        let calls = await counter.value
        XCTAssertEqual(calls, 1)

        // Subsequent currentAccessToken returns the refreshed value.
        let current = await auth.currentAccessToken()
        XCTAssertEqual(current, "fresh_from_partner")
    }

    func testInvalidateAndRefreshWithoutProviderThrowsTokenExpired() async throws {
        let auth = PayabliAuth(config: makeConfig(accessToken: "old", tokenProvider: nil))
        do {
            _ = try await auth.invalidateAndRefresh()
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testInvalidateAndRefreshCoalescesConcurrentCallers() async throws {
        let counter = Counter()
        let auth = PayabliAuth(config: makeConfig(
            accessToken: "old",
            tokenProvider: {
                await counter.increment()
                try await Task.sleep(nanoseconds: 20_000_000)
                return "fresh"
            }
        ))

        async let a = auth.invalidateAndRefresh()
        async let b = auth.invalidateAndRefresh()
        async let c = auth.invalidateAndRefresh()
        let results = try await [a, b, c]

        XCTAssertEqual(Set(results), ["fresh"])
        let calls = await counter.value
        XCTAssertEqual(calls, 1, "Concurrent refresh requests should share a single in-flight Task")
    }

    func testProviderErrorMapsToTokenExpired() async throws {
        struct ProviderError: Error {}
        let auth = PayabliAuth(config: makeConfig(
            accessToken: "old",
            tokenProvider: { throw ProviderError() }
        ))
        do {
            _ = try await auth.invalidateAndRefresh()
            XCTFail("expected throw")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

/// Simple actor counter for tracking concurrent calls in tests.
private actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}
