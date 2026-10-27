@testable import PayabliSDKTapToPay
import XCTest

/// What each internal failure says about itself, which is the reason a host error carries.
@available(iOS 16.7, *)
final class PayabliTTPErrorDescriptionTests: XCTestCase {
    func testAFailureWithAReasonDescribesItselfByThatReason() {
        let reason = "the words the failure carries"
        let carryingAReason: [PayabliTTPError] = [
            .attestationRevoked(reason: reason),
            .attestationFailed(reason: reason),
            .deviceSetupRequired(reason: reason),
            .deviceSetupRefused(reason: reason),
            .entryPointRefused(reason: reason),
            .configFailed(reason: reason),
            .readerSetupFailed(reason: reason),
            .readerUnavailable(reason: reason),
            .guardFailed(reason: reason),
            .readerDeviceRefused(reason: reason),
            .nfcFailed(reason: reason),
            .paymentNotOpened(reason: reason),
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
            (.readerHardwareUnsupported, "This device cannot take contactless payments"),
            (.cardPresentNotEnabled, "Card-present payments are not enabled for this paypoint"),
            (.activationCodeMalformed, "The activation code must be six digits"),
            (.cardDeclined(paymentTransId: "TXN"), "The card was refused"),
            (.outcomeUnknown(paymentTransId: "TXN"), "The payment outcome is not known")
        ]
        for (error, text) in described {
            XCTAssertEqual(error.localizedDescription, text, "\(error)")
        }
    }
}
