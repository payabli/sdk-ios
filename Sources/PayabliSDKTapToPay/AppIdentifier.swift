import Foundation

/// The App ID App Attest signs for: the app's App ID prefix, a period, and its bundle identifier.
///
/// The prefix comes from the Keychain access group an item lands in when it is written without
/// one, which is the app's own App ID. Only the part before the first period is taken, because a
/// host whose entitlement lists a shared group first changes that default group but not its prefix.
enum AppIdentifier {
    static func derive(
        accessGroup: String?,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> String? {
        guard let accessGroup,
              let bundleIdentifier, !bundleIdentifier.isEmpty,
              let period = accessGroup.firstIndex(of: "."),
              period != accessGroup.startIndex
        else { return nil }
        return "\(accessGroup[..<period]).\(bundleIdentifier)"
    }
}
