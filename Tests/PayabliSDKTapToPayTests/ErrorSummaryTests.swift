import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// What may be repeated about an error in a log or an event payload.
///
/// The rule these hold to: this SDK's own words travel, the service's do not. A
/// validation message can quote what was submitted, and both channels reach
/// places a person did not choose to send them.
final class ErrorSummaryTests: XCTestCase {
    func testTheSDKsOwnFailureTextTravels() {
        let summary = ErrorSummary.of(PayabliTTPError.attestationFailed(reason: "key unusable"))

        XCTAssertTrue(summary.contains("key unusable"), summary)
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
