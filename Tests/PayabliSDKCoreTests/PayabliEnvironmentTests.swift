@testable import PayabliSDKCore
import XCTest

final class PayabliEnvironmentTests: XCTestCase {
    func testBaseURLsMatchPRD() {
        // swiftlint:disable force_unwrapping
        XCTAssertEqual(
            PayabliEnvironment.sandbox.baseURL,
            URL(string: "https://api-sandbox.payabli.com")!
        )
        XCTAssertEqual(
            PayabliEnvironment.production.baseURL,
            URL(string: "https://api.payabli.com")!
        )
        // swiftlint:enable force_unwrapping
    }

    func testEntriesAreTheTwoCommittedEnvironments() {
        XCTAssertEqual(
            PayabliEnvironment.entries,
            [PayabliEnvironment.sandbox, PayabliEnvironment.production]
        )
    }

    func testACommittedEnvironmentIsOneInstanceEverywhere() {
        XCTAssertTrue(PayabliEnvironment.sandbox === PayabliEnvironment.entries.first)
    }

    func testEqualFieldsAreNotOneEnvironment() {
        // Equality is identity: a second value with an equal name and origin
        // stays a second environment.
        // swiftlint:disable force_unwrapping
        let twin = PayabliEnvironment(
            name: "sandbox",
            baseURL: URL(string: "https://api-sandbox.payabli.com")!
        )
        // swiftlint:enable force_unwrapping
        XCTAssertFalse(twin == PayabliEnvironment.sandbox)
    }

    func testNamesAreTheLowercaseIdentifiers() {
        XCTAssertEqual(PayabliEnvironment.sandbox.name, "sandbox")
        XCTAssertEqual(PayabliEnvironment.production.name, "production")
    }
}
