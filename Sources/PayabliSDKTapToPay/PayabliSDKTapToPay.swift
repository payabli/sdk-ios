import Foundation
import PayabliSDKCore

/// Module-level namespace for `PayabliSDKTapToPay` metadata.
///
/// `PayabliSDKTapToPay` provides card-present payments via Tap to Pay on
/// iPhone (Apple's `ProximityReader` framework, fronted by Payabli's
/// attestation + transaction services).
///
/// > Note: the enum is named `PayabliTapToPayModule` (not
/// > `PayabliSDKTapToPay`, which would collide with the module name under
/// > `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`; and not `PayabliTTP`, which is
/// > already the public facade class in this module). See the companion
/// > namespaces in `PayabliSDKCore` and `PayabliSDKPayIn` for the same
/// > rationale. RFC-0001 §5, PRD §5.
public enum PayabliTapToPayModule {
    public static let version: String = "1.0.0"
}
