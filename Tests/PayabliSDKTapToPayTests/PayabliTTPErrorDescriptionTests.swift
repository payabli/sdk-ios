@testable import PayabliSDKTapToPay
import XCTest

/// What each internal failure says about itself, which is the reason a host error carries.
final class PayabliTTPErrorDescriptionTests: XCTestCase {
    func testAFailureWithAReasonDescribesItselfByThatReason() {
        let reason = "the words the failure carries"
        let carryingAReason: [PayabliTTPError] = [
            .attestationRevoked(reason: reason),
            .attestationFailed(reason: reason),
            .configFailed(reason: reason),
            .readerSetupFailed(reason: reason),
            .nfcFailed(reason: reason),
            .initiateFailed(reason: reason),
            .updateFailed(reason: reason, paymentTransId: "TXN", capture: .unknown),
            .activationFailed(reason: reason),
            .networkError(reason: reason)
        ]
        for error in carryingAReason {
            XCTAssertEqual(error.errorDescription, reason, "\(error)")
        }
    }

    func testAFailureWithNoReasonIsStillDescribed() {
        let described: [(PayabliTTPError, String)] = [
            (.notInitialized, "PayabliTTP has not been initialized"),
            (.invalidState(current: .idle, attempted: "charge"), "Invalid state idle for charge"),
            (.notReady(current: .idle), "Reader not ready (state: idle)"),
            (.devicePendingActivation, "Device is pending activation"),
            (.tokenExpired, "Access token expired"),
            (.termsNotAccepted, "Contactless payment terms have not been accepted"),
            (.readerOSVersionNotSupported(), "This OS version does not support contactless payments"),
            (.cardDeclined(paymentTransId: "TXN"), "The card was refused"),
            (.outcomeUnknown(paymentTransId: "TXN"), "The payment outcome is not known")
        ]
        for (error, text) in described {
            XCTAssertEqual(error.localizedDescription, text, "\(error)")
        }
    }
}
