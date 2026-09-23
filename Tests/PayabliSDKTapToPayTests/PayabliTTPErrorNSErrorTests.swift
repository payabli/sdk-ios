import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// Verifies that every `PayabliTTPError` case bridges to an `NSError` with
/// the documented domain `"com.payabli.ttp"`, the documented stable per-case
/// integer code, and a non-empty `NSLocalizedDescriptionKey`.
///
/// The integer codes are part of the public API. `errorCode` assigns each one
/// explicitly, so what these tests hold is that every sampled case keeps the code
/// it publishes. Declaration order is not checked and cannot be: a case inserted
/// mid-enum, given a fresh code and added to the table below, passes.
final class PayabliTTPErrorNSErrorTests: XCTestCase {
    // MARK: - Domain

    func testAllErrorsUseTheTTPDomain() {
        for sample in Self.allSamples {
            XCTAssertEqual(
                (sample.error as NSError).domain,
                "com.payabli.ttp",
                "Wrong domain for \(sample.error)"
            )
        }
    }

    // MARK: - Stable codes

    func testAllErrorCodesMatchPublicContract() {
        for sample in Self.allSamples {
            XCTAssertEqual(
                (sample.error as NSError).code,
                sample.expectedCode,
                "Wrong code for \(sample.error)"
            )
        }
    }

    // MARK: - User info / localized description

    func testAllErrorsHaveNonEmptyLocalizedDescription() {
        for sample in Self.allSamples {
            let nsError = sample.error as NSError
            let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String
            XCTAssertNotNil(description, "Missing description for \(sample.error)")
            XCTAssertFalse(
                description?.isEmpty ?? true,
                "Empty description for \(sample.error)"
            )
        }
    }

    func testInvalidStateDescriptionIncludesAttemptedOperation() {
        let err = PayabliTTPError.invalidState(current: .ready, attempted: "charge")
        let description = (err as NSError).userInfo[NSLocalizedDescriptionKey] as? String
        XCTAssertNotNil(description)
        XCTAssertTrue(
            description?.contains("charge") ?? false,
            "Expected description to include attempted operation; got: \(description ?? "<nil>")"
        )
        XCTAssertTrue(description?.contains("Invalid state") ?? false)
    }

    func testNotReadyDescriptionMentionsReader() {
        let err = PayabliTTPError.notReady(current: .attestingDevice)
        let description = (err as NSError).userInfo[NSLocalizedDescriptionKey] as? String
        XCTAssertNotNil(description)
        XCTAssertTrue(
            description?.contains("not ready") ?? false,
            "Expected description to mention reader not ready; got: \(description ?? "<nil>")"
        )
    }

    func testReasonBearingErrorsForwardTheirReason() {
        let err = PayabliTTPError.nfcFailed(reason: "reader timed out")
        let description = (err as NSError).userInfo[NSLocalizedDescriptionKey] as? String
        XCTAssertEqual(description, "reader timed out")
    }

    // MARK: - Capture and payment

    /// A bridged caller reconciles from `userInfo`, so what the Swift type answers has to arrive there too.
    func testEveryErrorBridgesItsCaptureAndPayment() {
        for sample in Self.allSamples {
            let info = (sample.error as NSError).userInfo
            XCTAssertEqual(info["capture"] as? Int, sample.error.capture.rawValue, "Wrong capture for \(sample.error)")
            XCTAssertEqual(
                info["paymentTransId"] as? String,
                sample.error.paymentTransId,
                "Wrong payment for \(sample.error)"
            )
        }
    }

    func testOnlyAFailureAfterTheTapCanHaveTakenMoney() {
        let answers = Dictionary(
            uniqueKeysWithValues: Self.allSamples.map { ($0.expectedCode, $0.error.capture) }
        )
        XCTAssertEqual(answers[8], .notCharged, "a failed read with no payment opened charged nothing")
        XCTAssertEqual(answers[10], .unknown, "a failed close carries what it was given")
        XCTAssertEqual(answers[16], .notCharged, "a refusal is an answer that no money moved")
        XCTAssertEqual(answers[17], .unknown)
        let beforeTheTap = answers.filter { ![8, 10, 16, 17].contains($0.key) }
        XCTAssertEqual(Set(beforeTheTap.values), [.notCharged])
    }

    func testAFailedReadForAnOpenedPaymentMayHaveBeenCharged() {
        let err = PayabliTTPError.nfcFailed(reason: "x", paymentTransId: "TXN-9")
        XCTAssertEqual(err.capture, .unknown)
        XCTAssertEqual(err.paymentTransId, "TXN-9")
    }

    func testAFailedCloseAnswersTheCaptureAndPaymentItWasGiven() {
        let err = PayabliTTPError.updateFailed(reason: "x", paymentTransId: "TXN-9", capture: .charged)
        XCTAssertEqual(err.capture, .charged)
        XCTAssertEqual(err.paymentTransId, "TXN-9")
    }

    func testAFailureBeforeAPaymentWasOpenedNamesNone() {
        XCTAssertNil(PayabliTTPError.initiateFailed(reason: "x").paymentTransId)
        XCTAssertNil((PayabliTTPError.initiateFailed(reason: "x") as NSError).userInfo["paymentTransId"])
    }

    // MARK: - toPayabliNSError() helper

    func testToPayabliNSErrorPreservesPayabliErrorDomain() {
        let err: Error = PayabliTTPError.tokenExpired
        let nsError = err.toPayabliNSError()
        XCTAssertEqual(nsError.domain, "com.payabli.ttp")
        XCTAssertEqual(nsError.code, 11)
    }

    func testToPayabliNSErrorBridgesNonPayabliErrorsViaNSError() {
        struct DummyError: Error {}
        let err: Error = DummyError()
        let nsError = err.toPayabliNSError()
        XCTAssertNotEqual(nsError.domain, "com.payabli.ttp")
    }

    /// An attestation-time `tokenProvider` failure escapes `runAttestationPhase` as a core
    /// `PayabliGenericError`, not a `PayabliTTPError`. Absent this branch it would fall through
    /// Swift's default `as NSError` bridging and an ObjC / MAUI caller could not read the code.
    func testToPayabliNSErrorSurfacesCorePayabliErrorCode() {
        let err: Error = PayabliGenericError(
            code: .tokenProviderFailed,
            reason: "tokenProvider returned no usable token"
        )

        let nsError = err.toPayabliNSError()

        XCTAssertEqual(nsError.domain, "com.payabli.ttp")
        XCTAssertEqual(nsError.code, -3)
        XCTAssertEqual(
            nsError.userInfo["PayabliErrorCode"] as? String,
            PayabliErrorCode.tokenProviderFailed.rawValue
        )
        XCTAssertEqual(
            nsError.userInfo[NSLocalizedDescriptionKey] as? String,
            "tokenProvider returned no usable token"
        )
    }

    // MARK: - Sample table

    private struct ErrorSample {
        let error: PayabliTTPError
        let expectedCode: Int
    }

    private static let allSamples: [ErrorSample] = [
        ErrorSample(error: .notInitialized, expectedCode: 0),
        ErrorSample(error: .invalidState(current: .ready, attempted: "x"), expectedCode: 1),
        ErrorSample(error: .notReady(current: .idle), expectedCode: 2),
        ErrorSample(error: .devicePendingActivation, expectedCode: 3),
        ErrorSample(error: .attestationRevoked(reason: "x"), expectedCode: 4),
        ErrorSample(error: .attestationFailed(reason: "x"), expectedCode: 5),
        ErrorSample(error: .configFailed(reason: "x"), expectedCode: 6),
        ErrorSample(error: .readerSetupFailed(reason: "x"), expectedCode: 7),
        ErrorSample(error: .nfcFailed(reason: "x"), expectedCode: 8),
        ErrorSample(error: .initiateFailed(reason: "x"), expectedCode: 9),
        ErrorSample(error: .updateFailed(reason: "x", paymentTransId: "TXN", capture: .unknown), expectedCode: 10),
        ErrorSample(error: .tokenExpired, expectedCode: 11),
        ErrorSample(error: .activationFailed(reason: "x"), expectedCode: 12),
        ErrorSample(error: .networkError(reason: "x"), expectedCode: 13),
        ErrorSample(error: .termsNotAccepted, expectedCode: 14),
        ErrorSample(error: .readerOSVersionNotSupported, expectedCode: 15),
        ErrorSample(error: .cardDeclined(paymentTransId: "TXN"), expectedCode: 16),
        ErrorSample(error: .outcomeUnknown(paymentTransId: "TXN"), expectedCode: 17)
    ]
}
