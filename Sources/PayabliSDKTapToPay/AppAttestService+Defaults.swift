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
    /// The field is optional on the wire and descriptive only. On the versions this
    /// SDK supports the platform answers the model name, which `model` already
    /// carries, and an app holding the user-assigned-device-name entitlement gets
    /// the name its owner typed, which is routinely a person's. The sibling SDK
    /// omits it and says the same.
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
