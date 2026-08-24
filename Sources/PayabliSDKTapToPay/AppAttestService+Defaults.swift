import Foundation

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Default hardware identifier providers

//
// Injectable `@Sendable` closures; macOS test builds fall back to stand-ins.

extension AppAttestService {
    /// Blank when the platform has no identifier to give, which registration
    /// refuses. A value invented here is not an identifier: it differs per call,
    /// so every call registers a device and the failure never surfaces. The
    /// sibling SDK returns a blank for the same reason.
    static var defaultHardwareId: @Sendable () -> String {
        {
            #if canImport(UIKit)
                return hardwareId(from: UIDevice.current.identifierForVendor?.uuidString)
            #else
                return hardwareId(from: nil)
            #endif
        }
    }

    /// Separate from the platform call so the branch that matters can be reached
    /// without one: on any host that has an identifier to give, the closure above
    /// never takes it.
    static func hardwareId(from identifier: String?) -> String {
        identifier ?? ""
    }

    static var defaultDeviceName: @Sendable () -> String {
        {
            #if canImport(UIKit)
                return UIDevice.current.name
            #else
                return "macOS"
            #endif
        }
    }

    static var defaultModel: @Sendable () -> String {
        { model() }
    }

    /// Read over the field's own bytes, up to the first zero. `utsname.machine`
    /// is 256 of them, and neither a pointer rebound with a claimed capacity of
    /// one nor a C-string scan stays inside them. Same string, defined this way.
    ///
    /// Its own function so the provider above is one closure. Three nested is one
    /// more than the analyzer accepts, and the innermost of them is the predicate
    /// that does the bounding.
    static func model() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafeBytes(of: &sysinfo.machine) { raw in
            // Up to the first zero, and no further: `String(cString:)` keeps
            // reading until it finds one, which is the same unbounded read
            // whatever the pointer was bound with.
            //
            // Failable, so bytes that are not UTF-8 are blank rather than a string
            // with replacement characters in it. Blank is what registration
            // refuses; a substituted character is a model the service reads as a
            // different device.
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
