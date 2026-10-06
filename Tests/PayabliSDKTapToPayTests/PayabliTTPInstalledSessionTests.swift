@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

@MainActor
final class PayabliTTPInstalledSessionTests: XCTestCase {
    override func tearDown() {
        PayabliSession.resetForTesting()
        super.tearDown()
    }

    func testCreatingBeforeASessionIsInstalledThrowsSessionNotInitialized() async {
        do {
            _ = try await PayabliTTP.create()
            XCTFail("a facade was created with no session installed")
        } catch {
            XCTAssertEqual((error as? any PayabliError)?.type, .sessionNotInitialized)
            let bridged = error as NSError
            XCTAssertEqual(bridged.domain, "com.payabli.ttp")
            XCTAssertEqual(bridged.code, 1019)
        }
    }

    func testRunsOnTheInstalledSession() async throws {
        let installed = try await PayabliSession.initialize(config: PayabliConfig(
            entryPoint: "demo",
            environment: .sandbox,
            tokenProvider: { "tok" }
        ))

        let ttp = try await PayabliTTP.create()

        XCTAssertTrue(ttp.session === installed)
    }
}
