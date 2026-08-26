import Foundation
import PayabliSDKCore

/// Non-secret demo settings, in one place.
///
/// `Secrets` is gitignored and holds credentials, so ordinary settings cannot
/// live there. Anything here is safe to commit and safe to show on the
/// Configuration screen.
enum DemoConfiguration {
    /// Which Payabli backend every SDK facade in this app talks to.
    ///
    /// Pick it with the scheme: `PayabliDemo qa`, `PayabliDemo sandbox` and
    /// `PayabliDemo production` each pass `-PayabliEnvironment`, and the plain
    /// `PayabliDemo` scheme passes nothing and runs whatever was chosen last.
    /// Sandbox until something chooses, as the environment an integrator can
    /// reach.
    ///
    /// Remembered, because a launch argument reaches only the process it
    /// launched: a Home-screen tap or a `devicectl` launch passes none, and
    /// without the memory those would revert mid-test.
    ///
    /// Captured by the facades at launch, so the Config screen shows it
    /// read-only.
    static let environment: PayabliEnvironment = resolvedEnvironment()

    /// The paypoint for whichever environment is running, from
    /// `Secrets.entryPoints`.
    ///
    /// Derived rather than declared alongside the environment, so choosing a
    /// scheme cannot leave one paypoint's identifier pointed at another
    /// environment's host — a pairing that fails as `401 "The signature key was
    /// not found"` and reads like a bad credential.
    static var entryPoint: String {
        EntryPointLookup.entryPoint(from: Secrets.entryPoints, for: environment) ?? ""
    }

    /// Set when the running environment has no paypoint configured, so the
    /// Config screen can say which one is missing instead of showing a blank.
    static var entryPointProblem: String? {
        EntryPointLookup.problem(from: Secrets.entryPoints, for: environment)
    }

    static let environmentSource: String = {
        if argumentEnvironment() != nil {
            return "launch argument"
        }
        if rememberedEnvironment() != nil {
            return "remembered from a launch argument"
        }
        return "default"
    }()

    private static let environmentDefaultsKey = "PayabliEnvironment"

    private static func resolvedEnvironment() -> PayabliEnvironment {
        if let fromArgument = argumentEnvironment() {
            UserDefaults.standard.set(nameFor(fromArgument), forKey: environmentDefaultsKey)
            return fromArgument
        }
        return rememberedEnvironment() ?? .sandbox
    }

    private static func argumentEnvironment() -> PayabliEnvironment? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PayabliEnvironment"),
              index + 1 < arguments.count else { return nil }
        return environmentNamed(arguments[index + 1])
    }

    private static func rememberedEnvironment() -> PayabliEnvironment? {
        UserDefaults.standard.string(forKey: environmentDefaultsKey)
            .flatMap(environmentNamed)
    }

    private static func environmentNamed(_ name: String) -> PayabliEnvironment? {
        switch name.lowercased() {
        case "qa": return .qa
        case "sandbox": return .sandbox
        case "production": return .production
        default: return nil
        }
    }

    static func nameFor(_ environment: PayabliEnvironment) -> String {
        EntryPointLookup.name(for: environment)
    }

    /// The host the running environment resolves to, as a string, so a screen can
    /// show which service this build talks to without holding the environment.
    static var host: String {
        environment.baseURL.host ?? "—"
    }

    /// Which SDK this build links, for the Config tab.
    static var sdkVersion: String {
        PayabliCore.version
    }

    /// Resolves the bundled `LocalTokenServer` base URL at runtime.
    ///
    /// `127.0.0.1` means the Mac in the Simulator and the phone on a device, so
    /// the host is resolved per run. First match wins:
    ///
    /// 1. `-PayabliTokenHost <host>`, or the same `UserDefaults` key. Takes a
    ///    bare host, a `host:port`, or a full URL.
    /// 2. Simulator: `127.0.0.1`.
    /// 3. Device: `Secrets.localNetworkHost`, the Mac's Bonjour name, which
    ///    survives a DHCP lease change. Where mDNS is blocked, use (1).
    ///
    /// Running against a device needs the server bound past loopback and the
    /// Local Network permission; see `LocalTokenServer/README.md`.
    enum TokenServer {
        static let defaultPort = 8787
        static let accessTokenPath = "/payabli/access-token"

        /// Launch argument / `UserDefaults` key for the override.
        static let overrideKey = "PayabliTokenHost"

        enum Source {
            case override(String)
            case simulatorLoopback
            case deviceLocalNetwork
        }

        static var source: Source {
            if let raw = UserDefaults.standard.string(forKey: overrideKey),
               !raw.trimmingCharacters(in: .whitespaces).isEmpty
            {
                return .override(raw.trimmingCharacters(in: .whitespaces))
            }
            return TapToPayPreflight.runtimeEnvironment == .simulator
                ? .simulatorLoopback
                : .deviceLocalNetwork
        }

        /// Base URL, e.g. `http://127.0.0.1:8787`.
        static var baseURL: URL {
            switch source {
            case let .override(raw):
                return normalized(raw)
            case .simulatorLoopback:
                return url(host: "127.0.0.1", port: defaultPort)
            case .deviceLocalNetwork:
                return url(host: Secrets.localNetworkHost, port: defaultPort)
            }
        }

        static var accessTokenURL: URL {
            baseURL.appendingPathComponent(
                accessTokenPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            )
        }

        static var healthURL: URL {
            baseURL.appendingPathComponent("health")
        }

        /// One line for the Configuration screen, so the resolved host is never
        /// a guess.
        static var explanation: String {
            switch source {
            case .override:
                return "overridden by -\(overrideKey)"
            case .simulatorLoopback:
                return "Simulator, loopback to this Mac"
            case .deviceLocalNetwork:
                return "device, Secrets.localNetworkHost over the local network"
            }
        }

        // MARK: - Helpers

        /// Accepts a bare host, `host:port`, or a full URL, so the override can
        /// be pasted from whatever the person has to hand.
        private static func normalized(_ raw: String) -> URL {
            if raw.contains("://"), let parsed = URL(string: raw) {
                return parsed
            }
            if let colon = raw.lastIndex(of: ":"),
               let port = Int(raw[raw.index(after: colon)...])
            {
                return url(host: String(raw[raw.startIndex ..< colon]), port: port)
            }
            return url(host: raw, port: defaultPort)
        }

        private static func url(host: String, port: Int) -> URL {
            var components = URLComponents()
            components.scheme = "http"
            components.host = host
            components.port = port
            guard let built = components.url else {
                // `URLComponents` only fails here on a malformed host, which
                // means a bad override; fall back rather than trapping in a demo.
                return URL(string: "http://127.0.0.1:\(defaultPort)")!
            }
            return built
        }
    }

    /// How the SDK reached this build, read from the build configuration via
    /// `Info.plist`. See `Config/*.xcconfig` and the `Payabli SDK linkage`
    /// build phase — the configuration is the source of truth, this is a readout.
    enum Linkage {
        static var current: String {
            let raw = Bundle.main.object(forInfoDictionaryKey: "PayabliSDKLinkage") as? String
            guard let raw, !raw.isEmpty, !raw.hasPrefix("$(") else { return "unknown" }
            return raw
        }

        static var explanation: String {
            switch current {
            case "source": return "built from Package.swift on every build"
            case "xcframework": return "linked from prebuilt XCFrameworks"
            default: return "no PAYABLI_SDK_LINKAGE in the build configuration"
            }
        }
    }
}
