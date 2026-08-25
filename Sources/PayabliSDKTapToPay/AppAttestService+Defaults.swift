import Foundation

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Default hardware identifier providers

//
// Injectable `@Sendable` closures; macOS test builds fall back to stand-ins.

extension AppAttestService {
    /// `deviceName` is not sent, and there is no provider for it.
    ///
    /// It is optional on the wire and descriptive only: the platform answers the
    /// model name, which `model` already carries, and an app holding the
    /// user-assigned-device-name entitlement gets the name its owner typed.
    static var defaultModel: @Sendable () -> String {
        { model() }
    }

    /// Read over the field's own bytes, up to the first zero. `utsname.machine`
    /// is 256 of them, and neither a pointer rebound with a claimed capacity of
    /// one nor a C-string scan stays inside them.
    static func model() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafeBytes(of: &sysinfo.machine) { raw in
            // Failable, so bytes that are not UTF-8 are blank. Registration
            // refuses a blank; a replacement character is a model the service
            // reads as a different device.
            String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
    }

    static var defaultOSVersion: @Sendable () -> String {
        {
            #if canImport(UIKit)
                return UIDevice.current.systemVersion
            #else
                return ProcessInfo.processInfo.operatingSystemVersionString
            #endif
        }
    }
}
