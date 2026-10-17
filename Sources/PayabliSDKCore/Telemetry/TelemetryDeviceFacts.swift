import Foundation

/// What a telemetry event says about the device it came from, in the service's own words.
///
/// The transport adds them to every event, and no call site sets one. A blank fact, or one outside printable
/// ASCII, is left out.
package struct TelemetryDeviceFacts: Sendable, Equatable {
    /// The service's word for a card-present device.
    package static let cardPresentType = "Softpos"

    /// The service's word for this platform.
    package static let platform = "Ios"

    package let deviceType: String?
    package let deviceOs: String?
    package let osVersion: String?
    package let modelName: String?
    package let packageName: String?

    package init(
        deviceType: String?,
        deviceOs: String?,
        osVersion: String?,
        modelName: String?,
        packageName: String?
    ) {
        self.deviceType = Self.printable(deviceType)
        self.deviceOs = Self.printable(deviceOs)
        self.osVersion = Self.printable(osVersion)
        self.modelName = Self.printable(modelName)
        self.packageName = Self.printable(packageName)
    }

    /// The facts for this device and app. A device type is named only when the card-present product is
    /// linked, because a device that cannot register has no type in the service's vocabulary.
    ///
    /// - Returns: the facts the transport adds to every event.
    package static func current() -> TelemetryDeviceFacts {
        TelemetryDeviceFacts(
            deviceType: CardPresentLinkage.isLinked ? cardPresentType : nil,
            deviceOs: platform,
            osVersion: DeviceModel.osVersion(),
            modelName: DeviceModel.hardware(),
            packageName: Bundle.main.bundleIdentifier
        )
    }

    private static func printable(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              value.unicodeScalars.allSatisfy({ (0x20 ... 0x7E).contains($0.value) })
        else { return nil }
        return value
    }
}
