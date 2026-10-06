import Foundation
import PayabliSDKCore

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
        { DeviceModel.hardware() }
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
