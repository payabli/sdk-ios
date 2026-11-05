import PayabliSDKCore
import XCTest

final class PayabliErrorStatusTests: XCTestCase {
    /// A conformer of its own, as a component may write, that declares neither property.
    private struct ComponentError: PayabliError {
        var type: PayabliErrorType {
            .unknown
        }

        var reason: String {
            "component"
        }

        var detail: String? {
            nil
        }
    }

    func testAConformerThatDeclaresNeitherReadsNilForBoth() {
        let error: any PayabliError = ComponentError()

        XCTAssertNil(error.httpStatus)
        XCTAssertNil(error.rawCode)
    }

    func testAGenericErrorBuiltWithoutAnAnswerCarriesNeither() {
        let error: any PayabliError = PayabliGenericError(type: .networkError, reason: "offline")

        XCTAssertNil(error.httpStatus)
        XCTAssertNil(error.rawCode)
    }

    func testAGenericErrorBuiltFromAnAnswerCarriesItsStatusAndCode() {
        let error: any PayabliError = PayabliGenericError(
            type: .unknown,
            reason: "HTTP 418",
            httpStatus: 418,
            rawCode: "E1001"
        )

        XCTAssertEqual(error.httpStatus, 418)
        XCTAssertEqual(error.rawCode, "E1001")
    }

    func testAnObjectiveCSessionErrorCarriesTheStatusAndCodeUnderTheirNames() {
        let error = PayabliGenericError(type: .unknown, reason: "HTTP 418", httpStatus: 418, rawCode: "E1001")
            .payabliNSError(domain: "com.payabli.session")

        XCTAssertEqual(error.userInfo["httpStatus"] as? NSNumber, 418)
        XCTAssertEqual(error.userInfo["rawCode"] as? NSString, "E1001")
    }

    func testAnObjectiveCSessionErrorWithNeitherCarriesNeitherKey() {
        let error = PayabliGenericError(type: .networkError, reason: "offline")
            .payabliNSError(domain: "com.payabli.session")

        XCTAssertNil(error.userInfo["httpStatus"])
        XCTAssertNil(error.userInfo["rawCode"])
    }

    func testAnObjectiveCUnexpectedFailureCarriesItsCausesTypeAndNoneOfItsMessage() throws {
        let failure = try XCTUnwrap(HostFailure().payabliUnexpectedFailure)
            .payabliNSError(domain: "com.payabli.session")

        let cause = try XCTUnwrap(failure.userInfo[NSUnderlyingErrorKey] as? NSError)
        XCTAssertEqual(failure.code, 1017)
        XCTAssertEqual(cause.localizedDescription, String(reflecting: HostFailure.self))
        XCTAssertFalse("\(cause)".contains(HostFailure.message))
        XCTAssertFalse("\(failure)".contains(HostFailure.message))
    }

    func testAnObjectiveCErrorWhoseCauseIsNotRedactedCarriesNoUnderlyingError() {
        let error = PayabliGenericError(type: .unknown, reason: "r", underlying: HostFailure())
            .payabliNSError(domain: "com.payabli.session")

        XCTAssertNil(error.userInfo[NSUnderlyingErrorKey])
    }
}

/// A host's failure whose message names what the SDK must not repeat.
struct HostFailure: LocalizedError {
    static let message = "https://host.example/token?secret=1"

    var errorDescription: String? {
        Self.message
    }
}
