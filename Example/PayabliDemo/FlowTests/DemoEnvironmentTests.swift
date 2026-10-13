import PayabliSDKCore
import XCTest

/// The app shows its own environment type and the SDK decides where a request
/// goes, so a test bundle, which may name both, holds them against each other.
final class DemoEnvironmentTests: XCTestCase {
    private let committed = PayabliEnvironment.entries.map(DemoEnvironment.init)

    func testAnEnvironmentShowsWhatTheSDKCallsItAndWhereItPoints() {
        for environment in PayabliEnvironment.entries {
            let shown = DemoEnvironment(environment)
            XCTAssertEqual(shown.label, environment.name)
            XCTAssertEqual(shown.baseURL, environment.baseURL)
        }
    }

    func testALabelNamesItsEnvironmentWhateverItsCase() {
        XCTAssertEqual(DemoEnvironment.named("  SANDBOX \n", in: committed), .sandbox)
        XCTAssertEqual(DemoEnvironment.named("Production", in: committed), .production)
        XCTAssertNil(DemoEnvironment.named("staging", in: committed))
    }

    func testALabelOutsideTheOfferedListNamesNothing() {
        XCTAssertNil(DemoEnvironment.named("production", in: [.sandbox]))
    }

    func testTheFallbackIsReachableByAnIntegrator() {
        XCTAssertEqual(DemoEnvironment.fallback, .sandbox)
        XCTAssertTrue(committed.contains(DemoEnvironment.fallback))
    }
}
