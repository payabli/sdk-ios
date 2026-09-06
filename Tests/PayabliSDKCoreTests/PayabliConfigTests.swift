@testable import PayabliSDKCore
import XCTest

final class PayabliConfigTests: XCTestCase {
    private func makeConfig(
        accessToken: String = "partner_minted_token",
        entryPoint: String = "test_entry"
    ) throws -> PayabliConfig {
        try PayabliConfig(
            accessToken: accessToken,
            entryPoint: entryPoint,
            environment: .sandbox
        )
    }

    func testAValidConfigIsAccepted() throws {
        let config = try makeConfig()
        XCTAssertEqual(config.accessToken, "partner_minted_token")
        XCTAssertEqual(config.entryPoint, "test_entry")
    }

    /// Whitespace is printable ASCII, so a token of spaces passes the header check
    /// and would reach the wire carrying nothing.
    func testABlankAccessTokenIsRefused() throws {
        for blank in ["", " ", "   ", "\t", "\n", " \t\n "] {
            do {
                _ = try makeConfig(accessToken: blank)
                XCTFail("expected throw for \(blank.debugDescription)")
            } catch let err as PayabliGenericError {
                XCTAssertEqual(err.code, .invalidConfiguration, blank.debugDescription)
            }
        }
    }

    /// A CR or LF would be header injection on `Authorization`, and the platform
    /// drops the header rather than reporting it, so the request would go out
    /// unauthenticated.
    func testAnAccessTokenThatCannotBeAHeaderValueIsRefused() throws {
        for unusable in ["tok\r\nX-Injected: true", "tok\ten", "tok\u{0000}en", "tokén"] {
            do {
                _ = try makeConfig(accessToken: unusable)
                XCTFail("expected throw for \(unusable.debugDescription)")
            } catch let err as PayabliGenericError {
                XCTAssertEqual(err.code, .invalidConfiguration, unusable.debugDescription)
            }
        }
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

    /// The description reaches assertion failures and crash reports without passing
    /// the logger, so it carries neither the credential nor the merchant.
    func testTheDescriptionCarriesNeitherTheTokenNorTheEntryPoint() throws {
        let config = try PayabliConfig(
            accessToken: "SHOULD_NOT_BE_DESCRIBED",
            entryPoint: "MERCHANT_SHOULD_NOT_BE_DESCRIBED",
            environment: .sandbox
        )

        let rendered = "\(config) \(String(describing: config)) \(String(reflecting: config))"
        XCTAssertFalse(rendered.contains("SHOULD_NOT_BE_DESCRIBED"), rendered)
        XCTAssertFalse(rendered.contains("MERCHANT_SHOULD_NOT_BE_DESCRIBED"), rendered)
        XCTAssertTrue(rendered.contains("tokenProvider: absent"), rendered)
    }

    func testTheDescriptionSaysWhetherAProviderIsPresent() throws {
        let withProvider = try PayabliConfig(
            accessToken: "seed",
            tokenProvider: { "fresh" },
            entryPoint: "e",
            environment: .sandbox
        )
        XCTAssertTrue("\(withProvider)".contains("tokenProvider: present"), "\(withProvider)")
    }
}
