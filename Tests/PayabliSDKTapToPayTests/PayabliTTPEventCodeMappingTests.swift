import XCTest
import PayabliSDKTapToPay

/// Guards the public mapping between `PayabliTTPEvent` (Swift enum with
/// associated values) and `PayabliTTPEventCode` (`@objc Int` enum) plus the
/// `PayabliTTPEvent.payload` dictionary used by the
/// `addEventListener(handler:)` ObjC bridge.
///
/// The integer codes and the per-case payload schema are part of the public
/// API. Adding a new event case in the middle of this enum would silently
/// renumber the rest, breaking ObjC consumers that compare against literal
/// codes — these tests fail loudly if that happens.
final class PayabliTTPEventCodeMappingTests: XCTestCase {

    func testEventCodeRawValuesAreStable() {
        XCTAssertEqual(PayabliTTPEventCode.attestationStarted.rawValue, 0)
        XCTAssertEqual(PayabliTTPEventCode.attestationCompleted.rawValue, 1)
        XCTAssertEqual(PayabliTTPEventCode.configReceived.rawValue, 2)
        XCTAssertEqual(PayabliTTPEventCode.readerInitializing.rawValue, 3)
        XCTAssertEqual(PayabliTTPEventCode.readerReady.rawValue, 4)
        XCTAssertEqual(PayabliTTPEventCode.chargeInitiated.rawValue, 5)
        XCTAssertEqual(PayabliTTPEventCode.nfcStarted.rawValue, 6)
        XCTAssertEqual(PayabliTTPEventCode.nfcCompleted.rawValue, 7)
        XCTAssertEqual(PayabliTTPEventCode.nfcFailed.rawValue, 8)
        XCTAssertEqual(PayabliTTPEventCode.updateCompleted.rawValue, 9)
        XCTAssertEqual(PayabliTTPEventCode.updateFailed.rawValue, 10)
        XCTAssertEqual(PayabliTTPEventCode.sessionExpired.rawValue, 11)
        XCTAssertEqual(PayabliTTPEventCode.reinitializeStarted.rawValue, 12)
        XCTAssertEqual(PayabliTTPEventCode.reinitializeCompleted.rawValue, 13)
        XCTAssertEqual(PayabliTTPEventCode.devicePendingActivation.rawValue, 14)
        XCTAssertEqual(PayabliTTPEventCode.activationStarted.rawValue, 15)
        XCTAssertEqual(PayabliTTPEventCode.activationCompleted.rawValue, 16)
        XCTAssertEqual(PayabliTTPEventCode.activationFailed.rawValue, 17)
    }

    // MARK: - .code mapping

    func testCodeMappingForAllCases() {
        XCTAssertEqual(PayabliTTPEvent.attestationStarted.code, .attestationStarted)
        XCTAssertEqual(PayabliTTPEvent.attestationCompleted.code, .attestationCompleted)
        XCTAssertEqual(PayabliTTPEvent.configReceived.code, .configReceived)
        XCTAssertEqual(PayabliTTPEvent.readerInitializing.code, .readerInitializing)
        XCTAssertEqual(PayabliTTPEvent.readerReady.code, .readerReady)
        XCTAssertEqual(PayabliTTPEvent.chargeInitiated(paymentTransId: "x").code, .chargeInitiated)
        XCTAssertEqual(PayabliTTPEvent.nfcStarted.code, .nfcStarted)
        XCTAssertEqual(PayabliTTPEvent.nfcCompleted.code, .nfcCompleted)
        XCTAssertEqual(PayabliTTPEvent.nfcFailed(error: "x").code, .nfcFailed)
        XCTAssertEqual(PayabliTTPEvent.updateCompleted(paymentTransId: "x").code, .updateCompleted)
        XCTAssertEqual(PayabliTTPEvent.updateFailed(paymentTransId: "x", error: "y").code, .updateFailed)
        XCTAssertEqual(PayabliTTPEvent.sessionExpired.code, .sessionExpired)
        XCTAssertEqual(PayabliTTPEvent.reinitializeStarted.code, .reinitializeStarted)
        XCTAssertEqual(PayabliTTPEvent.reinitializeCompleted.code, .reinitializeCompleted)
        XCTAssertEqual(PayabliTTPEvent.devicePendingActivation.code, .devicePendingActivation)
        XCTAssertEqual(PayabliTTPEvent.activationStarted.code, .activationStarted)
        XCTAssertEqual(PayabliTTPEvent.activationCompleted.code, .activationCompleted)
        XCTAssertEqual(PayabliTTPEvent.activationFailed(error: "x").code, .activationFailed)
    }

    // MARK: - .payload schema

    func testPayloadEmptyForCasesWithoutAssociatedValues() {
        let emptyCases: [PayabliTTPEvent] = [
            .attestationStarted, .attestationCompleted, .configReceived,
            .readerInitializing, .readerReady, .nfcStarted, .nfcCompleted,
            .sessionExpired, .reinitializeStarted, .reinitializeCompleted,
            .devicePendingActivation, .activationStarted, .activationCompleted
        ]
        for event in emptyCases {
            XCTAssertTrue(event.payload.isEmpty,
                          "Expected empty payload for \(event.code)")
        }
    }

    func testChargeInitiatedPayloadCarriesPaymentTransId() {
        let payload = PayabliTTPEvent.chargeInitiated(paymentTransId: "TXN-1").payload
        XCTAssertEqual(payload.count, 1)
        XCTAssertEqual(payload["paymentTransId"] as? String, "TXN-1")
    }

    func testUpdateCompletedPayloadCarriesPaymentTransId() {
        let payload = PayabliTTPEvent.updateCompleted(paymentTransId: "TXN-2").payload
        XCTAssertEqual(payload.count, 1)
        XCTAssertEqual(payload["paymentTransId"] as? String, "TXN-2")
    }

    func testNfcFailedPayloadCarriesError() {
        let payload = PayabliTTPEvent.nfcFailed(error: "reader timeout").payload
        XCTAssertEqual(payload.count, 1)
        XCTAssertEqual(payload["error"] as? String, "reader timeout")
    }

    func testActivationFailedPayloadCarriesError() {
        let payload = PayabliTTPEvent.activationFailed(error: "bad code").payload
        XCTAssertEqual(payload.count, 1)
        XCTAssertEqual(payload["error"] as? String, "bad code")
    }

    func testUpdateFailedPayloadCarriesBothFields() {
        let payload = PayabliTTPEvent.updateFailed(paymentTransId: "TXN-3", error: "HTTP 500").payload
        XCTAssertEqual(payload.count, 2)
        XCTAssertEqual(payload["paymentTransId"] as? String, "TXN-3")
        XCTAssertEqual(payload["error"] as? String, "HTTP 500")
    }
}
