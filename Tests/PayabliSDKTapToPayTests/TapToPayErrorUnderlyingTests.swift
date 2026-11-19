@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// A card-present failure keeps the type of an error the SDK did not expect, and none of that error's message.
@available(iOS 16.7, *)
final class TapToPayErrorUnderlyingTests: XCTestCase {
    private struct HostThrew: Error, CustomStringConvertible {
        let message = "SENSITIVE-MARKER-4111"
        var description: String {
            message
        }
    }

    private func failure(underlying: RedactedCause? = nil) -> TapToPayError {
        TapToPayError(type: .unknown, reason: "Unknown", detail: nil, underlying: underlying)
    }

    func testAFailureBuiltWithoutACauseCarriesNone() {
        XCTAssertNil(failure().underlying)
        XCTAssertNil(failure().carrying(httpStatus: 500).underlying)
    }

    func testAFailureKeepsTheCauseItWasBuiltWith() throws {
        let cause = RedactedCause(HostThrew())

        let kept = try XCTUnwrap(failure(underlying: cause).underlying as? RedactedCause)

        XCTAssertEqual(kept, cause)
    }

    func testCarryingAStatusKeepsTheCause() throws {
        let cause = RedactedCause(HostThrew())

        let copy = failure(underlying: cause).carrying(httpStatus: 503)

        XCTAssertEqual(copy.httpStatus, 503)
        XCTAssertEqual(try XCTUnwrap(copy.underlying as? RedactedCause), cause)
    }

    func testNoDescriptionOfTheFailureCarriesTheCausesMessage() {
        let marker = HostThrew().message
        let error = failure(underlying: RedactedCause(HostThrew())).carrying(httpStatus: 500)
        let bridged = error as NSError

        XCTAssertFalse(String(describing: error).contains(marker))
        XCTAssertFalse(String(reflecting: error).contains(marker))
        XCTAssertFalse(error.localizedDescription.contains(marker))
        XCTAssertFalse(bridged.description.contains(marker))
        XCTAssertFalse(String(describing: bridged.userInfo).contains(marker))
        XCTAssertFalse(String(describing: error.underlying).contains(marker))
    }
}
