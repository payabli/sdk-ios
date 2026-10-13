import PayabliSDKCore
import XCTest

/// The app shows its own environment type and the SDK decides where a request
/// goes, so a test bundle, which may name both, holds them against each other.
final class DemoEnvironmentTests: XCTestCase {
    private let committed = PayabliEnvironment.entries.map(DemoEnvironment.init)

    func testProductionIsKnownByItsHostWhateverItIsNamed() throws {
        let renamed = try DemoEnvironment(label: "live", baseURL: XCTUnwrap(URL(string: "https://api.payabli.com")))
        XCTAssertTrue(renamed.pointsAtProduction)
        XCTAssertTrue(DemoEnvironment.production.pointsAtProduction)
        XCTAssertFalse(DemoEnvironment.sandbox.pointsAtProduction)
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
