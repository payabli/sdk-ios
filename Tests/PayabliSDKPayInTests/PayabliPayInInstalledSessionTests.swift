@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

@MainActor
final class PayabliPayInInstalledSessionTests: XCTestCase {
    override func tearDown() {
        PayabliSession.resetForTesting()
        super.tearDown()
    }

    func testConfigureWithTheInstalledConfigurationKeepsTheInstalledSession() throws {
        let installed = try PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))
        let component = PayabliPayIn(session: installed)

        component.configure(config: try makeConfig(entryPoint: "demo"))

        XCTAssertTrue(component.session === installed)
    }

    func testConfigureWithADifferentConfigurationRefusesTheNextSubmission() async throws {
        continueAfterFailure = false
        let installed = try PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))
        let component = PayabliPayIn(session: installed)

        component.configure(config: try makeConfig(entryPoint: "other"))
        XCTAssertTrue(component.session === installed, "configure built a second session")
        XCTAssertEqual(component.entryPoint, "demo", "a refused configuration was published")

        do {
            _ = try await component.capture(PayabliPayInRequest(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10),
                paymentMethod: .cash
            ))
            XCTFail("a submission after a refused configuration was sent")
        } catch {
            XCTAssertEqual((error as? PayabliGenericError)?.code, .invalidConfiguration)
        }
    }

    func testObjectiveCFacadeRunsOnTheInstalledSession() throws {
        let installed = try PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))

        let bridged = try PayabliPayInObjC.create()

        XCTAssertTrue(bridged.component.session === installed)
    }

    func testObjectiveCFacadeBeforeASessionIsInstalledThrows() {
        XCTAssertThrowsError(try PayabliPayInObjC.create())
    }

    func testObjectiveCEntryPointInstallsTheSessionSwiftReads() throws {
        try PayabliSessionObjC.initialize(
            tokenHandler: { completion in completion("tok", nil) },
            entryPoint: "demo",
            environment: .sandbox,
            telemetryEnabled: true
        )

        let bridged = try PayabliPayInObjC.create()
        let fromSwift = try PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))

        XCTAssertTrue(bridged.component.session === fromSwift)
    }

    func testObjectiveCEntryPointRefusesADifferentConfiguration() throws {
        try PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))

        XCTAssertThrowsError(try PayabliSessionObjC.initialize(
            tokenHandler: { completion in completion("tok", nil) },
            entryPoint: "other",
            environment: .sandbox,
            telemetryEnabled: true
        )) { error in
            XCTAssertEqual((error as? PayabliGenericError)?.code, .invalidConfiguration)
        }
    }

    private func makeConfig(entryPoint: String) throws -> PayabliConfig {
        try PayabliConfig(entryPoint: entryPoint, environment: .sandbox, tokenProvider: { "tok" })
    }
}
