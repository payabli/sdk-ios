@testable import PayabliDemo
import PayabliSDKCore
import XCTest

/// Which environment this run is against, and the credentials for it.
///
/// Chosen by `PAYABLI_ENV` in the test process's environment, which `xcodebuild`
/// fills from `TEST_RUNNER_PAYABLI_ENV`, so one build runs against QA and against
/// sandbox without a scheme per environment. A run with nothing set is refused
/// rather than defaulted: registering a device is a write, and it should land in
/// the environment somebody named.
enum LiveEnvironment {
    static func named() throws -> (environment: PayabliEnvironment, entry: String, name: String) {
        let requested = ProcessInfo.processInfo.environment["PAYABLI_ENV"]
        guard let requested, !requested.isEmpty else {
            throw XCTSkip("no PAYABLI_ENV; pass TEST_RUNNER_PAYABLI_ENV=qa or =sandbox")
        }
        let environment: PayabliEnvironment
        switch requested.lowercased() {
        case "qa": environment = .qa
        case "sandbox": environment = .sandbox
        default:
            XCTFail("PAYABLI_ENV=\(requested) names no environment this run can reach")
            throw XCTSkip("unusable PAYABLI_ENV")
        }
        let entry = try XCTUnwrap(
            Secrets.entryPoints[environment],
            "no paypoint configured for \(requested)"
        )
        pointAtTheServerFor(requested.lowercased())
        return (environment, entry, requested.lowercased())
    }

    /// One token server per environment, since a server holds one upstream, so the
    /// port is what separates them. The host is the demo's own — `localNetworkHost`
    /// on a device — unless the run names one.
    private static func pointAtTheServerFor(_ name: String) {
        if let host = ProcessInfo.processInfo.environment["PAYABLI_TOKEN_HOST"], !host.isEmpty {
            UserDefaults.standard.set(host, forKey: DemoConfiguration.TokenServer.overrideKey)
            return
        }
        let port = name == "sandbox" ? 8788 : 8787
        UserDefaults.standard.set(
            "\(Secrets.localNetworkHost):\(port)",
            forKey: DemoConfiguration.TokenServer.overrideKey
        )
    }

    /// A config pointed at the live environment, taking its token from the
    /// partner endpoint the demo app uses.
    static func config(for named: (environment: PayabliEnvironment, entry: String, name: String)) -> PayabliConfig {
        PayabliConfig(
            accessToken: Secrets.placeholderAccessToken,
            tokenProvider: { try await Secrets.fetchAccessToken() },
            entryPoint: named.entry,
            environment: named.environment
        )
    }

    /// Fails the run early when the token endpoint is unreachable, so a device
    /// that cannot see the Mac reports that rather than a string of attestation
    /// failures that name the wrong cause.
    static func requireAToken() async throws -> String {
        do {
            let token = try await Secrets.fetchAccessToken()
            guard !token.isEmpty else {
                throw XCTSkip("the token endpoint answered with an empty token")
            }
            return token
        } catch {
            throw XCTSkip(
                "no access token from \(Secrets.partnerTokenEndpoint.host ?? "the token endpoint"): \(error). "
                    + "Start LocalTokenServer bound to 0.0.0.0 and check the device is on the same network."
            )
        }
    }

    /// Printed so a run's output names the environment and paypoint it wrote to.
    static func announce(_ named: (environment: PayabliEnvironment, entry: String, name: String)) {
        print("PAYABLI_RUN env=\(named.name) entry=\(named.entry)")
    }
}
