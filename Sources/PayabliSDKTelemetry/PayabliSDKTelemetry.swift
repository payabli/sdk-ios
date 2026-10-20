import Foundation
import PayabliSDKCore

/// The telemetry module, carried by every SDK product.
public enum PayabliSDKTelemetry {
    public static var version: String {
        PayabliCore.version
    }
}
