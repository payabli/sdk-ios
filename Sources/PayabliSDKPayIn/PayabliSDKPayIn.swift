import Foundation
import PayabliSDKCore

// Supplies the bearer access token used by v2 MoneyIn transaction APIs.
//
// Prefer fetching this value from the host application's backend just before
// processing a transaction. Do not hard-code private API keys in an app binary.

/// Module-level namespace for `PayabliSDKPayIn` metadata.
///
/// The enum name differs from the module name, so a library-evolution build does not confuse a
/// namespace with the Swift module itself.
public enum PayabliPayInModule {
    public static var version: String {
        PayabliCore.version
    }
}
