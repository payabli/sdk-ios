@testable import PayabliSDKTapToPay
import XCTest

final class AppIdentifierTests: XCTestCase {
    private let bundle = "com.acme.checkout"

    func testTheAppsOwnGroupGivesItsPrefixAndTheBundle() {
        XCTAssertEqual(
            AppIdentifier.derive(accessGroup: "ABCDE12345.com.acme.checkout", bundleIdentifier: bundle),
            "ABCDE12345.com.acme.checkout"
        )
    }

    /// A host whose entitlement lists a shared group first changes the default group, and the
    /// whole group string is then another app's identifier.
    func testASharedGroupGivesTheSamePrefixAndThisAppsBundle() {
        XCTAssertEqual(
            AppIdentifier.derive(accessGroup: "ABCDE12345.com.acme.shared", bundleIdentifier: bundle),
            "ABCDE12345.com.acme.checkout"
        )
    }

    func testAPrefixThatIsNotTheTeamIdIsKept() {
        XCTAssertEqual(
            AppIdentifier.derive(accessGroup: "9Z8Y7X6W5V.com.acme.checkout", bundleIdentifier: bundle),
            "9Z8Y7X6W5V.com.acme.checkout"
        )
    }

    func testNoGroupGivesNothing() {
        XCTAssertNil(AppIdentifier.derive(accessGroup: nil, bundleIdentifier: bundle))
    }

    func testAGroupWithNoPrefixGivesNothing() {
        XCTAssertNil(AppIdentifier.derive(accessGroup: "checkout", bundleIdentifier: bundle))
        XCTAssertNil(AppIdentifier.derive(accessGroup: ".com.acme.checkout", bundleIdentifier: bundle))
    }

    func testNoBundleGivesNothing() {
        XCTAssertNil(AppIdentifier.derive(accessGroup: "ABCDE12345.com.acme.checkout", bundleIdentifier: nil))
        XCTAssertNil(AppIdentifier.derive(accessGroup: "ABCDE12345.com.acme.checkout", bundleIdentifier: ""))
    }
}
