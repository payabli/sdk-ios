import PayabliSDKCore
import XCTest

/// The demo names its own environments, so this app can show which service it
/// points at without a screen holding an SDK type.
///
/// That leaves two lists of hosts. The SDK's is the one that decides where a
/// request goes; this app's is what it shows a reader. A test bundle may name an
/// SDK type, so this is where the two are held against each other.
final class DemoEnvironmentTests: XCTestCase {
    func testEveryEnvironmentPointsWhereTheSDKPointsIt() {
        for environment in DemoEnvironment.allCases {
            XCTAssertEqual(
                environment.baseURL,
                environment.sdkEnvironment.baseURL,
                "\(environment.label) shows a host the SDK does not use"
            )
        }
    }

    func testTheDemoKnowsEveryEnvironmentTheSDKOffers() {
        let named = DemoEnvironment.allCases.map(\.sdkEnvironment)
        XCTAssertEqual(Set(named).count, DemoEnvironment.allCases.count)
        for environment in PayabliEnvironment.entries {
            XCTAssertTrue(
                named.contains(environment),
                "the demo offers no environment for \(environment.name)"
            )
        }
    }

    func testALabelNamesItsEnvironmentWhateverItsCase() {
        XCTAssertEqual(DemoEnvironment.named("  SANDBOX \n"), .sandbox)
        XCTAssertEqual(DemoEnvironment.named("Production"), .production)
        XCTAssertNil(DemoEnvironment.named("staging"))
    }

    func testTheFallbackIsReachableByAnIntegrator() {
        XCTAssertEqual(DemoEnvironment.fallback, .sandbox)
    }
}
