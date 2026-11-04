import PayabliSDKCore
import PayabliSDKTapToPay
import XCTest

/// The line a failed action leaves on the Tap to Pay tab.
final class ActionLineTests: XCTestCase {
    private struct Refusal: PayabliError {
        var type: PayabliErrorType {
            .paymentDeclined
        }

        var reason: String {
            "The merchant declined the terms."
        }

        var detail: String? {
            nil
        }
    }

    private struct Thrown: PayabliError {
        let type: PayabliErrorType

        var reason: String {
            "The service's own text."
        }

        var detail: String? {
            nil
        }
    }

    private struct Shown: DisplayedFailure {
        let message = "This iPhone can't do that."
    }

    func testAFailureIsTheMarkPlusItsCategorysMessageAndNeverItsOwnText() {
        XCTAssertEqual(ActionLine.failed(Refusal()), "✗ The payment was declined.")
    }

    func testAFailureThatAlreadyCarriesItsMessageKeepsIt() {
        XCTAssertEqual(ActionLine.failed(Shown()), "✗ This iPhone can't do that.")
        XCTAssertEqual(ActionLine.message(for: Shown()), "This iPhone can't do that.")
    }

    func testAnOldOperatingSystemSaysToUpdateIt() {
        XCTAssertEqual(
            ActionLine.message(for: Thrown(type: .deviceOSUnsupported)),
            "This iPhone's iOS version is too old for Tap to Pay. Update iOS and try again."
        )
    }

    func testUnsupportedHardwareSaysThisIPhoneCannotTakeTapToPay() {
        XCTAssertEqual(
            ActionLine.message(for: Thrown(type: .deviceHardwareUnsupported)),
            "This iPhone can't take Tap to Pay payments."
        )
    }

    func testARefusedDeviceSaysToContactSupportWithTheDeviceId() {
        XCTAssertEqual(
            ActionLine.message(for: Thrown(type: .readerDeviceRefused)),
            "This iPhone isn't set up for Tap to Pay with this app. Contact Payabli support with the device ID on the Config tab."
        )
    }

    func testAnUnidentifiableDeviceSaysTapToPayCannotStart() {
        XCTAssertEqual(
            ActionLine.message(for: Thrown(type: .deviceIdentityUnavailable)),
            "This iPhone can't be identified, so Tap to Pay can't start."
        )
    }

    func testAnotherDeviceFailureKeepsTheCategoryLine() {
        XCTAssertEqual(ActionLine.message(for: Thrown(type: .deviceSetupUnsupported)), "This iPhone can't do that.")
    }

    func testAChargeThatMayHaveBeenTakenSaysSoWhateverItsCategory() {
        XCTAssertEqual(
            ActionLine.chargeMessage(for: Thrown(type: .readerUnavailable), capture: .unknown, paymentTransId: "txn-1"),
            "This payment may have gone through. Check before charging again. · txn txn-1"
        )
    }

    func testAChargedCardSaysNotToChargeItAgain() {
        XCTAssertEqual(
            ActionLine.chargeMessage(for: Thrown(type: .paymentNotClosed), capture: .charged, paymentTransId: "txn-2"),
            "The card was charged. Don't charge it again. · txn txn-2"
        )
    }

    func testAFailureNamingNoPaymentCarriesNoTransactionId() {
        XCTAssertEqual(
            ActionLine.chargeMessage(for: Thrown(type: .readerUnavailable), capture: .unknown, paymentTransId: nil),
            "This payment may have gone through. Check before charging again."
        )
    }

    func testAnUnchargedFailureKeepsItsCategoryLine() {
        XCTAssertEqual(
            ActionLine.chargeMessage(for: Thrown(type: .readerUnavailable), capture: .notCharged, paymentTransId: "txn-3"),
            "That didn't work. Please try again."
        )
        XCTAssertEqual(
            ActionLine.chargeMessage(for: Thrown(type: .deviceOSUnsupported), capture: .notCharged, paymentTransId: nil),
            "This iPhone's iOS version is too old for Tap to Pay. Update iOS and try again."
        )
    }
}
