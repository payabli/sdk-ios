import Foundation
import PayabliSDKCore

/// Module-level namespace for `PayabliSDKPayIn` metadata.
///
/// `PayabliSDKPayIn` provides tokenization, card-not-present processing
/// (getpaid), and card-present payments via Tap to Pay on iPhone.
///
/// > Note: the enum is named `PayabliPayInModule` (not `PayabliSDKPayIn`,
/// > which would collide with the module name under
/// > `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`; and not `PayabliPayIn`, which
/// > is already the public facade class in this module). See the
/// > companion namespace in `PayabliSDKCore` for the same rationale.
/// > RFC-0001 §5, PRD §5.
public enum PayabliPayInModule {
    public static let version: String = "1.0.0"
}
