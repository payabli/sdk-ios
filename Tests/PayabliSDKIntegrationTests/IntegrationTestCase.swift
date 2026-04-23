import XCTest
import PayabliSDKCore

/// Base class for integration tests that hit `api-sandbox.payabli.com`.
///
/// These tests are **gated by environment variables** and are skipped when
/// credentials are not supplied, so CI without secrets still passes. To run:
///
/// ```sh
/// PAYABLI_SANDBOX_ACCESS_TOKEN="..." \
/// PAYABLI_SANDBOX_CUSTOMER_ID="4440" \
/// PAYABLI_SANDBOX_ENTRY_POINT="..." \
/// swift test --filter PayabliSDKIntegrationTests
/// ```
///
/// The access token comes from your partner backend's `/payabli/token`-style
/// endpoint (the SDK's own `PayabliAuth` does not mint tokens — §8 Auth).
class IntegrationTestCase: XCTestCase {

    struct SandboxCreds {
        let accessToken: String
        let customerId: Int
        let entryPoint: String
    }

    /// Loads credentials from env vars. Throws `XCTSkip` when missing.
    func sandboxCreds() throws -> SandboxCreds {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["PAYABLI_SANDBOX_ACCESS_TOKEN"], !token.isEmpty,
              let customer = env["PAYABLI_SANDBOX_CUSTOMER_ID"].flatMap(Int.init),
              let entry = env["PAYABLI_SANDBOX_ENTRY_POINT"], !entry.isEmpty else {
            throw XCTSkip("Set PAYABLI_SANDBOX_* env vars to run integration tests")
        }
        return SandboxCreds(
            accessToken: token,
            customerId: customer,
            entryPoint: entry
        )
    }

    func sandboxConfig() throws -> PayabliConfig {
        let creds = try sandboxCreds()
        return PayabliConfig(
            accessToken: creds.accessToken,
            entryPoint: creds.entryPoint,
            environment: .sandbox
        )
    }
}
