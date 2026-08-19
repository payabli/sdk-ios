import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// What may be repeated about an error in a log or an event payload.
///
/// The rule these hold to: this SDK's own words travel, the service's do not. A
/// validation message can quote what was submitted, and both channels reach
/// places a person did not choose to send them.
final class ErrorSummaryTests: XCTestCase {
    /// The same case carries this SDK's words on one path and the service's on
    /// another, so no reason is repeated and the case is what the summary says.
    func testNoReasonIsRepeated() {
        let sdksOwnWords = "key unusable"
        let serversWords = "Card belongs to another merchant"

        XCTAssertEqual(ErrorSummary.of(PayabliTTPError.attestationFailed(reason: sdksOwnWords)), "attestationFailed")
        XCTAssertEqual(ErrorSummary.of(PayabliTTPError.configFailed(reason: serversWords)), "configFailed")
        XCTAssertEqual(ErrorSummary.of(PayabliTTPError.readerSetupFailed(reason: sdksOwnWords)), "readerSetupFailed")
        XCTAssertEqual(ErrorSummary.of(PayabliTTPError.activationFailed(reason: serversWords)), "activationFailed")
    }

    /// The charge cases carry what the service said about a charge, taken from the
    /// envelope in `TTPTransactionClient`.
    func testChargeFailuresAreNamedWithoutTheirReason() {
        let serversWords = "Card belongs to another merchant"

        XCTAssertEqual(ErrorSummary.of(PayabliTTPError.initiateFailed(reason: serversWords)), "initiateFailed")
        XCTAssertEqual(ErrorSummary.of(PayabliTTPError.updateFailed(reason: serversWords)), "updateFailed")
    }

    /// Written out case by case, so a value the compiler renders differently one
    /// release to the next cannot change what host apps receive.
    func testTheSummaryIsNotAReflectedDescription() {
        let summary = ErrorSummary.of(PayabliTTPError.notReady(current: .idle))

        XCTAssertEqual(summary, "notReady(current: idle)")
    }

    /// Every case, with what it publishes. The summary is a contract with host
    /// apps, so a case whose text changes should fail here rather than reach one.
    ///
    /// A reason is passed wherever the case takes one, and none of them appears in
    /// what is published.
    func testEveryCasePublishesItsName() {
        let reason = "Card belongs to another merchant"
        let expected: [(PayabliTTPError, String)] = [
            (.notInitialized, "notInitialized"),
            (.invalidState(current: .ready, attempted: "charge"), "invalidState(current: ready, attempted: charge)"),
            (.notReady(current: .attestingDevice), "notReady(current: attestingDevice)"),
            (.devicePendingActivation, "devicePendingActivation"),
            (.tokenExpired, "tokenExpired"),
            (.attestationRevoked(reason: reason), "attestationRevoked"),
            (.attestationFailed(reason: reason), "attestationFailed"),
            (.configFailed(reason: reason), "configFailed"),
            (.readerSetupFailed(reason: reason), "readerSetupFailed"),
            (.nfcFailed(reason: reason), "nfcFailed"),
            (.activationFailed(reason: reason), "activationFailed"),
            (.networkError(reason: reason), "networkError"),
            (.initiateFailed(reason: reason), "initiateFailed"),
            (.updateFailed(reason: reason), "updateFailed")
        ]

        for (error, published) in expected {
            let summary = ErrorSummary.of(error)

            XCTAssertEqual(summary, published)
            XCTAssertFalse(summary.contains(reason), summary)
        }
    }

    /// Each state by name, because an `@objc` enum renders as its raw value and a
    /// log that says `rawValue: 6` costs the reader a trip to the source.
    func testEveryStateIsNamed() {
        let expected: [(PayabliTTPSessionState, String)] = [
            (.idle, "idle"),
            (.attestingDevice, "attestingDevice"),
            (.fetchingConfig, "fetchingConfig"),
            (.initializingReader, "initializingReader"),
            (.ready, "ready"),
            (.sessionExpired, "sessionExpired"),
            (.reinitializing, "reinitializing"),
            (.pendingActivation, "pendingActivation"),
            (.error, "error")
        ]

        for (state, name) in expected {
            XCTAssertEqual(ErrorSummary.of(PayabliTTPError.notReady(current: state)), "notReady(current: \(name))")
        }
    }

    func testATypedServiceErrorReducesToItsCode() {
        let error = PayabliGenericError(code: .tokenExpired, reason: "The signature key was not found")

        let summary = ErrorSummary.of(error)

        XCTAssertEqual(summary, PayabliErrorCode.tokenExpired.rawValue)
        XCTAssertFalse(summary.contains("signature key"), summary)
    }

    /// The umbrella bridges to a domain and an ordinal on its own, which is the
    /// `error 1` shape this SDK stopped showing anyone.
    func testTheUmbrellaIsUnwrappedBeforeItsCodeIsRead() throws {
        // Decoded rather than constructed, as the core tests do: the memberwise
        // initialiser of a public `Decodable` struct is internal.
        let body = Data(#"{"title":"Validation failed","status":400,"detail":"Card belongs to another merchant"}"#.utf8)
        let validation = try JSONDecoder().decode(PayabliValidationError.self, from: body)

        let summary = ErrorSummary.of(PayabliPaymentError.validation(validation))

        XCTAssertEqual(summary, PayabliErrorCode.validation.rawValue)
        XCTAssertFalse(summary.contains("another merchant"), summary)
    }

    func testAPlatformErrorReportsItsDomainAndCode() {
        let error = NSError(
            domain: "NSURLErrorDomain",
            code: -1009,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )

        let summary = ErrorSummary.of(error)

        XCTAssertEqual(summary, "NSURLErrorDomain(-1009)")
        XCTAssertFalse(summary.contains("offline"), summary)
    }
}
