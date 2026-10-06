@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

@MainActor
final class PayabliPayInInstalledSessionTests: XCTestCase {
    override func tearDown() {
        PayabliSession.resetForTesting()
        super.tearDown()
    }

    func testConfigureWithTheInstalledConfigurationKeepsTheInstalledSession() async throws {
        let installed = try await PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))
        let component = PayabliPayIn(session: installed)

        component.configure(config: try makeConfig(entryPoint: "demo"))

        XCTAssertTrue(component.session === installed)
    }

    func testConfigureWithADifferentConfigurationRefusesTheNextSubmission() async throws {
        continueAfterFailure = false
        let installed = try await PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))
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
            XCTAssertEqual((error as? PayabliGenericError)?.type, .invalidConfiguration)
        }
    }

    func testObjectiveCFacadeRunsOnTheInstalledSession() async throws {
        let installed = try await PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))

        let bridged = try PayabliPayInObjC.create()

        XCTAssertTrue(bridged.component.session === installed)
    }

    func testObjectiveCFacadeBeforeASessionIsInstalledThrowsSessionNotInitialized() {
        XCTAssertThrowsError(try PayabliPayInObjC.create()) { error in
            assertCatalogError(error, domain: "com.payabli.payIn", type: .sessionNotInitialized)
        }
    }

    func testObjectiveCEntryPointInstallsTheSessionSwiftReads() async throws {
        try await PayabliSessionObjC.initialize(
            tokenHandler: { completion in completion("tok", nil) },
            entryPoint: "demo",
            environment: .sandbox,
            telemetryEnabled: true
        )

        let bridged = try PayabliPayInObjC.create()
        let fromSwift = try await PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))

        XCTAssertTrue(bridged.component.session === fromSwift)
    }

    func testObjectiveCEntryPointRefusesADifferentConfiguration() async throws {
        try await PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))

        do {
            try await PayabliSessionObjC.initialize(
                tokenHandler: { completion in completion("tok", nil) },
                entryPoint: "other",
                environment: .sandbox,
                telemetryEnabled: true
            )
            XCTFail("a different configuration was accepted")
        } catch {
            assertCatalogError(error, domain: "com.payabli.session")
        }
    }

    func testObjectiveCEntryPointRefusesABlankEntryPoint() async {
        do {
            try await PayabliSessionObjC.initialize(
                tokenHandler: { completion in completion("tok", nil) },
                entryPoint: " ",
                environment: .sandbox,
                telemetryEnabled: true
            )
            XCTFail("a blank entry point was accepted")
        } catch {
            assertCatalogError(error, domain: "com.payabli.session")
            XCTAssertEqual((error as NSError).localizedDescription, "Invalid configuration: entryPoint is blank.")
        }
    }

    /// What an Objective-C caller reads: the domain, the catalog number as the code, and the wire name.
    private func assertCatalogError(
        _ error: Error,
        domain: String,
        type: PayabliErrorType = .invalidConfiguration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let nsError = error as NSError
        XCTAssertEqual(nsError.domain, domain, file: file, line: line)
        XCTAssertEqual(nsError.code, type.number, file: file, line: line)
        XCTAssertEqual(
            nsError.userInfo["PayabliErrorType"] as? String,
            type.rawValue,
            file: file,
            line: line
        )
    }

    private func makeConfig(entryPoint: String) throws -> PayabliConfig {
        try PayabliConfig(entryPoint: entryPoint, environment: .sandbox, tokenProvider: { "tok" })
    }
}
