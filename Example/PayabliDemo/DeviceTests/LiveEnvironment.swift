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

    /// What a run may print, following `PayabliLogger`'s rules: a transaction id, a
    /// code or a state is public, a device identifier is not, and a token is never
    /// logged at any level.
    ///
    /// Test output is retained by Xcode and by CI, so the identifiers a run needs in
    /// order to be acted on — the handle an activation code is requested for — are
    /// printed only when a run asks for them.
    static func report(_ line: String) {
        print(line)
    }

    /// A device identifier, printed only when `PAYABLI_REPORT_IDENTIFIERS` is set.
    static func reportIdentifier(_ name: String, _ value: String, env: String) {
        guard let ask = ProcessInfo.processInfo.environment["PAYABLI_REPORT_IDENTIFIERS"],
              !ask.isEmpty
        else {
            print("PAYABLI_\(name) env=\(env) withheld=set PAYABLI_REPORT_IDENTIFIERS to print it")
            return
        }
        print("PAYABLI_\(name) env=\(env) value=\(value)")
    }
}
