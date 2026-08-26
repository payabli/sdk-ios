@testable import PayabliDemo
import PayabliSDKCore
import XCTest

/// Which environment this run is against, and the credentials for it.
///
/// Two things are required, and the environment alone is not enough. `PAYABLI_ENV`
/// names which paypoint, and `PAYABLI_QA_LIVE` opts the run in. Everything reached
/// from here registers a device and moves money, and the scheme carries the
/// environment, so without the second one an operator opening the scheme and
/// pressing Test charges a paypoint. `QAWalkthroughUITests` gates its walkthrough
/// on the same variable for the same reason.
///
/// Both come from the scheme's environment for an app-hosted bundle: the
/// `TEST_RUNNER_` prefix reaches a UI-test runner and not a host application.
enum LiveEnvironment {
    /// The name the walkthrough already uses, so one flag opts into every live run
    /// rather than one per suite.
    static let liveRunKey = "PAYABLI_QA_LIVE"

    static func named() throws -> (environment: PayabliEnvironment, entry: String, name: String) {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment[liveRunKey] == "1",
            "set \(liveRunKey)=1 in the scheme to register a device and move money"
        )

        let requested = ProcessInfo.processInfo.environment["PAYABLI_ENV"]
        guard let requested, !requested.isEmpty else {
            throw XCTSkip("no PAYABLI_ENV; set it in the scheme to qa or sandbox")
        }
        let environment: PayabliEnvironment
        switch requested.lowercased() {
        case "qa": environment = .qa
        case "sandbox": environment = .sandbox
        default:
            XCTFail("PAYABLI_ENV=\(requested) names no environment this run can reach")
            throw XCTSkip("unusable PAYABLI_ENV")
        }
        // Keyed by name, because the credentials file names no SDK type.
        let entry = try XCTUnwrap(
            EntryPointLookup.entryPoint(from: Secrets.entryPoints, for: environment),
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
