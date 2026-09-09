@testable import PayabliSDKCore
import XCTest

final class PayabliConfigTests: XCTestCase {
    private func makeConfig(
        entryPoint: String = "test_entry",
        tokenProvider: @escaping PayabliTokenRefresh = { "partner_minted_token" }
    ) throws -> PayabliConfig {
        try PayabliConfig(
            entryPoint: entryPoint,
            environment: .sandbox,

            tokenProvider: tokenProvider
        )
    }

    func testAValidConfigIsAccepted() throws {
        let config = try makeConfig()
        XCTAssertEqual(config.entryPoint, "test_entry")
        XCTAssertEqual(config.environment, .sandbox)
    }

    func testABlankEntryPointIsRefused() throws {
        for blank in ["", "  ", "\t"] {
            do {
                _ = try makeConfig(entryPoint: blank)
                XCTFail("expected throw for \(blank.debugDescription)")
            } catch let err as PayabliGenericError {
                XCTAssertEqual(err.code, .invalidConfiguration, blank.debugDescription)
            }
        }
    }

    /// What the provider returns is checked where it is installed, not here. This pins that the
    /// config accepts a provider it cannot evaluate, so an unusable token is a run-time refusal on
    /// the request path rather than a construction-time one.
    func testAConfigIsAcceptedWithoutCallingItsProvider() async throws {
        let counter = Counter()
        _ = try makeConfig(tokenProvider: {
            _ = await counter.increment()
            return ""
        })
        let calls = await counter.count
        XCTAssertEqual(calls, 0, "the provider ran during construction")
    }

    /// The description reaches assertion failures and crash reports without passing
    /// the logger, so it carries neither the credential nor the merchant.
    func testTheDescriptionCarriesNeitherTheTokenNorTheEntryPoint() throws {
        let config = try PayabliConfig(
            entryPoint: "MERCHANT_SHOULD_NOT_BE_DESCRIBED",
            environment: .sandbox,

            tokenProvider: { "SHOULD_NOT_BE_DESCRIBED" }
        )

        let rendered = "\(config) \(String(describing: config)) \(String(reflecting: config))"
        XCTAssertFalse(rendered.contains("SHOULD_NOT_BE_DESCRIBED"), rendered)
        XCTAssertFalse(rendered.contains("MERCHANT_SHOULD_NOT_BE_DESCRIBED"), rendered)
    }
}
