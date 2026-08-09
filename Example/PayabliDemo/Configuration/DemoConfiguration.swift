import Foundation
import PayabliSDKCore

/// Non-secret demo settings, in one place.
///
/// Split deliberately from `Secrets`: that file is gitignored and holds
/// credentials, so it must not become the home of ordinary settings. Anything
/// here is safe to commit and safe to show on the Configuration screen.
enum DemoConfiguration {

    /// Which Payabli backend every SDK facade in this app talks to.
    ///
    /// Captured by the three facades at launch (`PayabliDemoQAApp`), so changing
    /// it needs a rebuild — which is why the Configuration screen displays it
    /// rather than editing it.
    static let environment: PayabliEnvironment = .qa

    /// Resolves the bundled `LocalTokenServer` base URL at runtime.
    ///
    /// The Simulator and a physical device disagree about what `127.0.0.1`
    /// means — on the phone it is the phone — so the host cannot be a constant.
    /// This picks it per run, and lets QA override it without a rebuild.
    ///
    /// Resolution order, first match wins:
    ///
    /// 1. **`-PayabliTokenHost <host>`** as a launch argument, or the same key
    ///    in `UserDefaults`. Beats everything, needs no recompile, and takes a
    ///    bare host (`192.168.10.42`), a `host:port`, or a full URL.
    /// 2. **Simulator** → `127.0.0.1`, which reaches the Mac directly.
    /// 3. **Physical device** → `Secrets.localNetworkHost`, the Mac's Bonjour
    ///    name. A `.local` name is preferred over a pinned IP because it
    ///    survives a DHCP lease change; where mDNS is blocked, override with (1).
    ///
    /// The device path needs the server bound beyond loopback:
    ///
    /// ```bash
    /// PAYABLI_LOCAL_TOKEN_SERVER_HOST=0.0.0.0 node server.mjs
    /// ```
    ///
    /// and `NSLocalNetworkUsageDescription` in `Info.plist`, since iOS 14 gates
    /// mDNS and local-subnet traffic behind the Local Network permission prompt.
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
               !raw.trimmingCharacters(in: .whitespaces).isEmpty {
                return .override(raw.trimmingCharacters(in: .whitespaces))
            }
            return TapToPayPreflight.runtimeEnvironment == .simulator
                ? .simulatorLoopback
                : .deviceLocalNetwork
        }

        /// Base URL, e.g. `http://127.0.0.1:8787`.
        static var baseURL: URL {
            switch source {
            case .override(let raw):
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
               let port = Int(raw[raw.index(after: colon)...]) {
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
