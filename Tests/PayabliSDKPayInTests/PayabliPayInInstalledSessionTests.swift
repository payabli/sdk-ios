@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import PayabliSDKTestUtils
import XCTest

@MainActor
final class PayabliPayInInstalledSessionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
        // A refusal reports at once, and a report would otherwise ask the host's token handler and reach the network.
        PayabliSession.resetForTesting(telemetryTransport: DiscardingTelemetryTransport())
    }

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
                paymentMethod: .cash,
                options: PayabliPayInRequestConfiguration(
                    paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10)
                )
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
            environment: .sandbox
        )

        let bridged = try PayabliPayInObjC.create()
        let fromSwift = try await PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))

        XCTAssertTrue(bridged.component.session === fromSwift)
    }

    func testObjectiveCEntryPointRefusesADifferentConfiguration() async throws {
        // Installed with a test transport, because the refusal reports at once.
        _ = try PayabliSession.install(config: makeConfig(entryPoint: "demo"), telemetryTransport: DiscardingTelemetryTransport())

        do {
            try await PayabliSessionObjC.initialize(
                tokenHandler: { completion in completion("tok", nil) },
                entryPoint: "other",
                environment: .sandbox
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
                environment: .sandbox
            )
            XCTFail("a blank entry point was accepted")
        } catch {
            assertCatalogError(error, domain: "com.payabli.session")
            XCTAssertEqual((error as NSError).localizedDescription, "Invalid configuration: entryPoint is blank.")
        }
    }

    func testAnOperationInFlightWhenItsSessionIsReplacedIsNotCountedUnderTheNewOne() async throws {
        let events = InMemoryTelemetryTransport()
        PayabliSession.resetForTesting(telemetryTransport: events)
        let minting = ProviderGate()
        let first = try PayabliSession.install(
            config: PayabliConfig(
                entryPoint: "first",
                environment: .sandbox,
                tokenProvider: { try await minting.held() }
            ),
            urlSession: RefusingURLProtocol.makeSession(),
            telemetryTransport: events
        )
        let component = PayabliPayIn(session: first)
        let capture = Task {
            try await component.capture(PayabliPayInRequest(
                paymentMethod: .cash,
                options: PayabliPayInRequestConfiguration(paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10))
            ))
        }
        await minting.called()
        // A session is replaced only once its credential is finished.
        first.machine.finish()

        let second = try await PayabliSession.initialize(config: makeConfig(entryPoint: "second"))
        component.configure(config: try makeConfig(entryPoint: "second"))
        await minting.open()
        _ = try? await capture.value
        await TelemetryRecorders.settled()
        await TelemetryRecorders.flush()

        let reported = await events.batches.flatMap { $0 }.filter { $0.event == TelemetryEventName.payinCaptureCompleted }
        XCTAssertTrue(component.session === first, "configure moved the flow to the new session")
        XCTAssertFalse(second === first)
        XCTAssertTrue(reported.isEmpty, "a capture begun on the replaced session was counted under the new one")
    }

    func testConfigureAfterItsSessionWasReplacedRefusesTheNextSubmission() async throws {
        let first = try await PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))
        let component = PayabliPayIn(session: first)
        first.machine.finish()
        let second = try await PayabliSession.initialize(config: makeConfig(entryPoint: "demo"))

        component.configure(config: try makeConfig(entryPoint: "demo"))

        XCTAssertFalse(second === first)
        XCTAssertTrue(component.session === first, "configure moved the flow to the new session")
        do {
            _ = try await component.capture(PayabliPayInRequest(
                paymentMethod: .cash,
                options: PayabliPayInRequestConfiguration(paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10))
            ))
            XCTFail("a flow configured after its session was replaced sent a submission")
        } catch {
            XCTAssertEqual((error as? PayabliGenericError)?.type, .invalidConfiguration)
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
        XCTAssertEqual(PayabliErrorTypeCode(rawValue: nsError.code), type.code, file: file, line: line)
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

/// Holds the token provider's call until opened, so a test can act while a request waits on its credential.
private actor ProviderGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var callers: [CheckedContinuation<Void, Never>] = []
    private var wasCalled = false

    func held() async throws -> String {
        wasCalled = true
        callers.forEach { $0.resume() }
        callers.removeAll()
        if !isOpen {
            await withCheckedContinuation { waiting.append($0) }
        }
        return "tok"
    }

    func called() async {
        if wasCalled {
            return
        }
        await withCheckedContinuation { callers.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

/// Fails every request at once, so a test reaches no network and waits on no timeout.
private final class RefusingURLProtocol: URLProtocol {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefusingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
