import Foundation
@testable import PayabliSDKCore
import XCTest

/// The conversion every public entry point applies to an error it does not know.
final class PayabliErrorUnexpectedFailureTests: XCTestCase {
    private struct HostThrew: Error {
        let message = "a message the boundary must not carry"
    }

    func testACancellationPassesThroughUnconverted() {
        XCTAssertNil(CancellationError().payabliUnexpectedFailure)
    }

    func testAnErrorTheSdkAlreadyClassifiedPassesThrough() {
        XCTAssertNil(PayabliGenericError(type: .networkError, reason: "offline").payabliUnexpectedFailure)
    }

    func testAnUnrecognizedErrorBecomesTheCatalogsUnknownFailure() throws {
        let failure = try XCTUnwrap(HostThrew().payabliUnexpectedFailure)

        XCTAssertEqual(failure.type, .unknown)
        XCTAssertEqual(failure.code, PayabliErrorType.unknown.number)
        XCTAssertEqual(failure.reason, PayabliErrorType.unknown.message)
        XCTAssertNil(failure.detail)
    }

    func testTheFailingTypeNameRidesTheRedactedCauseAndItsMessageNeverCrosses() throws {
        let failure = try XCTUnwrap(HostThrew().payabliUnexpectedFailure)
        let redacted = try XCTUnwrap(failure.underlying as? RedactedCause)

        XCTAssertEqual(redacted.originalType, String(reflecting: type(of: HostThrew())))
        XCTAssertFalse(failure.reason.contains(HostThrew().message))
        XCTAssertNil(failure.detail)
        XCTAssertFalse(redacted.originalType.contains(HostThrew().message))
    }

    func testAPlatformTransportErrorConvertsToo() throws {
        let failure = try XCTUnwrap(URLError(.notConnectedToInternet).payabliUnexpectedFailure)

        XCTAssertEqual(failure.type, .unknown)
        XCTAssertEqual(failure.reason, PayabliErrorType.unknown.message)
    }
}
