@testable import PayabliSDKTapToPay
import XCTest

/// Verifies that every `PayabliTTPError` case bridges to an `NSError` with
/// the documented domain `"com.payabli.ttp"`, the documented stable per-case
/// integer code, and a non-empty `NSLocalizedDescriptionKey`.
///
/// The integer codes are part of the public API. Inserting a new error case
/// in the middle of `PayabliTTPError` would silently renumber the rest, so
/// these tests fail loudly to remind us to append-only.
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
        ErrorSample(error: .updateFailed(reason: "x"), expectedCode: 10),
        ErrorSample(error: .tokenExpired, expectedCode: 11),
        ErrorSample(error: .activationFailed(reason: "x"), expectedCode: 12),
        ErrorSample(error: .networkError(reason: "x"), expectedCode: 13)
    ]
}
