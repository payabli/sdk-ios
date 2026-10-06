import Foundation

#if canImport(UIKit)
    import UIKit
#endif

package enum DeviceModel {
    /// Read over the field's own bytes, up to the first zero. `utsname.machine`
    /// is 256 of them, and neither a pointer rebound with a claimed capacity of
    /// one nor a C-string scan stays inside them.
    package static func hardware() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafeBytes(of: &sysinfo.machine) { raw in
            // Failable, so bytes that are not UTF-8 are blank. Registration
            // refuses a blank; a replacement character is a model the service
            // reads as a different device.
            String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
    }

    package static func osVersion() -> String {
        #if canImport(UIKit)
            return UIDevice.current.systemVersion
        #else
            return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
}
