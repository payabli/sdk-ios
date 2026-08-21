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
                return UIDevice.current.identifierForVendor?.uuidString ?? ""
            #else
                return ""
            #endif
        }
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

    /// Read over the field's own bytes. `utsname.machine` is 256 of them, and
    /// rebinding a pointer with a claimed capacity of one leaves reading the C
    /// string past what the call bound. Same string, defined this way.
    static var defaultModel: @Sendable () -> String {
        {
            var sysinfo = utsname()
            uname(&sysinfo)
            let raw = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
                guard let base = raw.baseAddress else { return "" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
            return raw.trimmingCharacters(in: .controlCharacters)
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
