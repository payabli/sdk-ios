@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

@MainActor
final class PayabliTTPInstalledSessionTests: XCTestCase {
    override func tearDown() {
        PayabliSession.resetForTesting()
        super.tearDown()
    }

    func testConstructingBeforeASessionIsInstalledThrowsNotInitialized() {
        XCTAssertThrowsError(try PayabliTTP(appId: "TEAM.app")) { error in
            guard case .notInitialized = error as? PayabliTTPError else {
                return XCTFail("expected notInitialized, got \(error)")
            }
        }
    }

    func testRunsOnTheInstalledSession() throws {
        let installed = try PayabliSession.initialize(config: PayabliConfig(
            entryPoint: "demo",
            environment: .sandbox,
            tokenProvider: { "tok" }
        ))

        let ttp = try PayabliTTP(appId: "TEAM.app")

        XCTAssertTrue(ttp.session === installed)
    }
}
