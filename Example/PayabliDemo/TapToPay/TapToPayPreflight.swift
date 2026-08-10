import DeviceCheck
import Foundation
#if canImport(ProximityReader)
import ProximityReader
#endif

/// Credential-independent pre-flight checks for the Tap to Pay tab.
///
/// Every check here resolves on its own. In particular, whether the app is on a
/// Simulator or a physical device is decided without reading the team ID, the
/// access token, or the entitlement — so a missing credential can never make the
/// host look like the wrong kind of machine, and a correct credential can never
/// make a Simulator look shippable.
///
/// Nothing in here reaches the network and nothing reads a secret.
enum TapToPayPreflight {

    // MARK: - Result model

    struct Check: Identifiable {
        enum Status {
            case pass
            case warn
            case fail
            case unknown
        }

        let id = UUID()
        let title: String
        let detail: String
        let status: Status
    }

    // MARK: - Host kind

    enum RuntimeEnvironment {
        case simulator
        case physicalDevice

        var label: String {
            switch self {
            case .simulator: return "Simulator"
            case .physicalDevice: return "Physical device"
            }
        }
    }

    /// Three independent signals, so this does not rest on one mechanism:
    ///   1. `targetEnvironment(simulator)` — decided at compile time, and a
    ///      Simulator slice cannot execute on a device, so it cannot be spoofed
    ///      by configuration.
    ///   2. `SIMULATOR_DEVICE_NAME` — only ever present in a Simulator process.
    ///   3. `uname` machine — a Simulator reports the host architecture
    ///      (`arm64` / `x86_64`); a device reports a model such as `iPhone17,1`.
    static var runtimeEnvironment: RuntimeEnvironment {
        #if targetEnvironment(simulator)
        return .simulator
        #else
        if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
            return .simulator
        }
        if ["arm64", "x86_64", "i386"].contains(machineIdentifier) {
            return .simulator
        }
        return .physicalDevice
        #endif
    }

    /// `uname` machine string: a device model identifier, or the host
    /// architecture when running under the Simulator.
    static var machineIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

    // MARK: - Platform capability

    /// App Attest availability, straight from DeviceCheck. Independent of the
    /// entitlement file and of any Payabli credential — it is `false` on a
    /// Simulator no matter how the target is signed.
    static var appAttestSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    /// `nil` when ProximityReader is not in the build at all.
    ///
    /// Do not read this alone as "ready": a Simulator answers `true` while being
    /// unable to attest or read a card, which is why `checks` cross-references it
    /// against `runtimeEnvironment`.
    static var tapToPayHardwareSupported: Bool? {
        #if canImport(ProximityReader)
        if #available(iOS 16.7, *) {
            return PaymentCardReader.isSupported
        }
        return false
        #else
        return nil
        #endif
    }

    // MARK: - Provisioning

    /// Entitlements from the embedded provisioning profile, or `nil` when there
    /// is no profile — which is the normal case for a Simulator build.
    ///
    /// `embedded.mobileprovision` is a CMS-signed container, so the XML plist is
    /// sliced out rather than decoded as a whole.
    ///
    /// Cached, because a provisioning profile cannot change during a process
    /// lifetime and reading it means slicing a plist out of a CMS container.
    static let provisioningEntitlements: [String: Any]? = loadProvisioningEntitlements()

    private static func loadProvisioningEntitlements() -> [String: Any]? {
        guard
            let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url),
            let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(
                of: Data("</plist>".utf8),
                options: [],
                in: start.lowerBound ..< data.endIndex
            )
        else {
            return nil
        }

        let plist = data[start.lowerBound ..< end.upperBound]
        guard
            let profile = try? PropertyListSerialization.propertyList(
                from: plist,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return nil
        }
        return profile["Entitlements"] as? [String: Any]
    }

    /// `nil` when no profile is embedded, so "absent" is never confused with
    /// "unknowable".
    static var proximityReaderEntitlementPresent: Bool? {
        guard let entitlements = provisioningEntitlements else { return nil }
        return entitlements["com.apple.developer.proximity-reader.payment.acceptance"] as? Bool ?? false
    }

    /// The Team ID this binary is actually signed with, read from the profile
    /// rather than from `Secrets`. That is what lets the App ID check below
    /// compare the configured value against reality instead of against itself.
    static var resolvedTeamIdentifier: String? {
        guard let entitlements = provisioningEntitlements else { return nil }
        if let team = entitlements["com.apple.developer.team-identifier"] as? String {
            return team
        }
        if let applicationIdentifier = entitlements["application-identifier"] as? String,
           let prefix = applicationIdentifier.split(separator: ".").first {
            return String(prefix)
        }
        return nil
    }

    // MARK: - Readiness rollup

    /// Whether the terminal can be used at all.
    ///
    /// Lives here rather than in a view so the Tap to Pay tab and the
    /// Configuration tab cannot reach different conclusions from the same facts.
    /// `Check.Status` is deliberately not `Comparable` — the checks are
    /// independent and there is no meaningful ordering between them — so the
    /// rollup is stated explicitly instead of derived from a max().
    enum Readiness {
        case ready
        case notAvailable

        var title: String {
            switch self {
            case .ready: return "Terminal Ready"
            case .notAvailable: return "Terminal Not Available"
            }
        }
    }

    /// `.notAvailable` if and only if some check hard-failed. A `.warn` or
    /// `.unknown` is a caveat worth showing, not a blocker.
    static func readiness(from checks: [Check]) -> Readiness {
        checks.contains { $0.status == .fail } ? .notAvailable : .ready
    }

    // MARK: - Assembled report

    static func checks(configuredAppId: String) -> [Check] {
        let environment = runtimeEnvironment
        let bundleId = Bundle.main.bundleIdentifier ?? "<unknown>"

        var results: [Check] = []

        // 1. Host kind — resolved before, and regardless of, any credential.
        results.append(
            Check(
                title: "Host: \(environment.label)",
                detail: environment == .simulator
                    ? "uname reports \(machineIdentifier). Tap to Pay needs a physical iPhone XS "
                        + "or later on iOS 16.7+; a Simulator cannot attest or read a card even "
                        + "with a valid team, token, and entitlement."
                    : "uname reports \(machineIdentifier).",
                status: environment == .simulator ? .fail : .pass
            )
        )

        // 2. App Attest, straight from DeviceCheck.
        results.append(
            Check(
                title: appAttestSupported ? "App Attest available" : "App Attest unavailable",
                detail: appAttestSupported
                    ? "DCAppAttestService reports support, so attestation can run."
                    : "DCAppAttestService reports no support, so initialize() fails during attestation.",
                status: appAttestSupported ? .pass : .fail
            )
        )

        // 3. Reader hardware, cross-referenced so a Simulator's `true` is not read as ready.
        switch tapToPayHardwareSupported {
        case true where environment == .simulator:
            results.append(
                Check(
                    title: "Reader support reported, but not trustworthy here",
                    detail: "PaymentCardReader.isSupported is true in the Simulator. It is not a "
                        + "usable signal off-device.",
                    status: .warn
                )
            )
        case true:
            results.append(
                Check(
                    title: "Reader hardware supported",
                    detail: "PaymentCardReader.isSupported is true on this device.",
                    status: .pass
                )
            )
        case false:
            results.append(
                Check(
                    title: "Reader hardware unsupported",
                    detail: "PaymentCardReader.isSupported is false, so the eligibility gate fails.",
                    status: .fail
                )
            )
        case nil:
            results.append(
                Check(
                    title: "ProximityReader not in this build",
                    detail: "The framework could not be imported.",
                    status: .unknown
                )
            )
        }

        // 4. Entitlement, read from the embedded profile.
        switch proximityReaderEntitlementPresent {
        case true:
            results.append(
                Check(
                    title: "Tap to Pay entitlement present",
                    detail: "The provisioning profile carries "
                        + "com.apple.developer.proximity-reader.payment.acceptance.",
                    status: .pass
                )
            )
        case false:
            results.append(
                Check(
                    title: "Tap to Pay entitlement missing",
                    detail: "The profile does not carry "
                        + "com.apple.developer.proximity-reader.payment.acceptance. Apple grants it "
                        + "on request, per target and team.",
                    status: .fail
                )
            )
        case nil:
            results.append(
                Check(
                    title: "No provisioning profile embedded",
                    detail: "Normal for a Simulator build, so the entitlement cannot be verified "
                        + "from here. Check it on a device build.",
                    status: .unknown
                )
            )
        }

        // 5. App ID, compared against the signing identity rather than against itself.
        results.append(appIdCheck(configuredAppId: configuredAppId, bundleId: bundleId))

        return results
    }

    private static func appIdCheck(configuredAppId: String, bundleId: String) -> Check {
        guard !configuredAppId.hasPrefix("ABCDE12345") else {
            return Check(
                title: "App ID is the sample placeholder",
                detail: "Set Secrets.appId to <TeamID>.\(bundleId).",
                status: .fail
            )
        }

        guard configuredAppId.hasSuffix(".\(bundleId)") else {
            return Check(
                title: "App ID does not match this bundle",
                detail: "Secrets.appId is \(configuredAppId) but this app is \(bundleId). "
                    + "App Attest rejects the mismatch.",
                status: .fail
            )
        }

        guard let team = resolvedTeamIdentifier else {
            // Simulator, or an unsigned build: the suffix is all that is checkable.
            return Check(
                title: "App ID matches this bundle",
                detail: "Team ID cannot be verified without an embedded profile; only the bundle "
                    + "suffix was checked.",
                status: .warn
            )
        }

        let expected = "\(team).\(bundleId)"
        guard configuredAppId == expected else {
            return Check(
                title: "App ID team prefix is wrong",
                detail: "This binary is signed by team \(team), so Secrets.appId should be "
                    + "\(expected).",
                status: .fail
            )
        }

        return Check(
            title: "App ID matches the signing identity",
            detail: "\(expected), verified against the embedded profile.",
            status: .pass
        )
    }
}
