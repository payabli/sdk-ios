@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// Every public card-present call hands a host an error the SDK did not expect as `UNKNOWN`, naming the failing type
/// in `underlying` and never its message. A cancellation and an error the SDK already classified pass through as they
/// were.
@available(iOS 16.7, *)
@MainActor
final class TapToPayUnexpectedFailureTests: XCTestCase {
    /// A collaborator's error whose message must never reach a host.
    private struct HostThrew: LocalizedError {
        var errorDescription: String? {
            "MESSAGE-SENTINEL"
        }
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = Self.handler
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - An error the SDK did not expect

    func testInitializeConvertsAForeignError() async throws {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.attestResult = .failure(HostThrew())

        try await assertConverted { try await ttp.initialize() }
    }

    func testInitializeConvertsAForeignErrorFromEachSetupStage() async throws {
        for ttp in try terminalsFailingEachSetupStage(with: HostThrew()) {
            try await assertConverted { try await ttp.initialize() }
        }
    }

    /// Activation is a setup run, which converts a foreign error itself to the SDK's internal error. It still names the
    /// type and never the message.
    func testActivateDeviceConvertsAForeignErrorInsideItsRun() async throws {
        let (ttp, _, attestation, _) = try await makePendingTTP()
        attestation.activationResult = .failure(HostThrew())

        do {
            try await ttp.activateDevice(activationCode: "123456")
            XCTFail("expected the activation to fail")
        } catch let error as TapToPayError {
            XCTAssertEqual(error.type, .sdkInternalError)
            XCTAssertEqual((error.underlying as? RedactedCause)?.simpleTypeName, "HostThrew")
            XCTAssertFalse("\(error)".contains("MESSAGE-SENTINEL"))
        }
    }

    func testChargeConvertsAForeignError() async throws {
        let (ttp, provider, _, _) = try await makeReadyTTP()
        provider.readingResult = .failure(HostThrew())

        try await assertConverted {
            _ = try await ttp.charge(paymentDetails: PayabliTTPPaymentDetails(amount: 1, currency: .usd))
        }
    }

    /// The sale may be taken once the reader is asked, so a cancelled read names its payment.
    func testACancelledReadIsATapThatDidNotCompleteNamingItsPayment() async throws {
        let (ttp, provider, _, _) = try await makeReadyTTP()
        provider.readingResult = .failure(CancellationError())

        do {
            _ = try await ttp.charge(paymentDetails: PayabliTTPPaymentDetails(amount: 1, currency: .usd))
            XCTFail("expected the charge to fail")
        } catch let error as TapToPayError {
            XCTAssertEqual(error.type, .tapNotCompleted)
            XCTAssertEqual(error.paymentTransId, "TXN-1")
            XCTAssertEqual(error.capture, .unknown)
        }
    }

    func testTheTermsCallsConvertAForeignError() async throws {
        let (ttp, provider, _, _) = try makeTTP()
        provider.areTermsAcceptedResult = .failure(HostThrew())
        provider.presentTermsResult = .failure(HostThrew())

        try await assertConverted { _ = try await ttp.areTermsAccepted() }
        try await assertConverted { try await ttp.presentTerms() }
    }

    // MARK: - What passes through

    func testACancellationPassesThroughEveryEntryPoint() async throws {
        let (ttp, provider, attestation, _) = try makeTTP()
        attestation.attestResult = .failure(CancellationError())
        provider.areTermsAcceptedResult = .failure(CancellationError())
        provider.presentTermsResult = .failure(CancellationError())

        try await assertPassesThrough(CancellationError.self) { try await ttp.initialize() }
        try await assertPassesThrough(CancellationError.self) { _ = try await ttp.areTermsAccepted() }
        try await assertPassesThrough(CancellationError.self) { try await ttp.presentTerms() }

        let (pending, _, pendingAttestation, _) = try await makePendingTTP()
        pendingAttestation.activationResult = .failure(CancellationError())
        try await assertPassesThrough(CancellationError.self) {
            try await pending.activateDevice(activationCode: "123456")
        }
    }

    func testACancellationFromEachSetupStagePassesThroughInitialize() async throws {
        for ttp in try terminalsFailingEachSetupStage(with: CancellationError()) {
            try await assertPassesThrough(CancellationError.self) { try await ttp.initialize() }
        }
    }

    func testAnErrorTheSDKClassifiedFromEachSetupStagePassesThroughInitialize() async throws {
        let classified = TapToPayError(type: .deviceSetupRequired, reason: "already classified", detail: "kept")
        for ttp in try terminalsFailingEachSetupStage(with: classified) {
            do {
                try await ttp.initialize()
                XCTFail("expected initialize to fail")
            } catch let error as TapToPayError {
                XCTAssertEqual(error.type, .deviceSetupRequired)
                XCTAssertEqual(error.reason, "already classified")
                XCTAssertEqual(error.detail, "kept")
            }
        }
    }

    func testAnErrorTheSDKClassifiedPassesThroughUnchanged() async throws {
        let classified = TapToPayError(type: .deviceSetupRequired, reason: "already classified", detail: "kept")
        let (ttp, provider, attestation, _) = try makeTTP()
        attestation.attestResult = .failure(classified)
        provider.areTermsAcceptedResult = .failure(classified)

        for call in [{ try await ttp.initialize() }, { _ = try await ttp.areTermsAccepted() }] {
            do {
                try await call()
                XCTFail("expected the call to fail")
            } catch let error as TapToPayError {
                XCTAssertEqual(error.type, .deviceSetupRequired)
                XCTAssertEqual(error.reason, "already classified")
                XCTAssertEqual(error.detail, "kept")
                XCTAssertNil(error.underlying)
            }
        }
    }

    /// A throwing token provider reaches the entry point already classified, its cause already redacted.
    func testATokenProviderFailureKeepsItsClassificationAndRedactedCause() async throws {
        let (ttp, _, _, _) = try makeTTP(tokenProvider: { throw HostThrew() })

        do {
            try await ttp.initialize()
            return XCTFail("expected initialize to fail")
        } catch let error as TapToPayError {
            XCTAssertEqual(error.type, .tokenProviderFailed)
            XCTAssertEqual((error.underlying as? RedactedCause)?.simpleTypeName, "HostThrew")
            XCTAssertFalse("\(error)".contains("MESSAGE-SENTINEL"))
            let bridged = error.toPayabliNSError()
            let cause = try XCTUnwrap(bridged.userInfo[NSUnderlyingErrorKey] as? NSError)
            XCTAssertTrue(cause.localizedDescription.hasSuffix("HostThrew"), cause.localizedDescription)
            XCTAssertFalse("\(bridged.userInfo)".contains("MESSAGE-SENTINEL"))
        }
    }

    // MARK: - Objective-C

    func testTheObjectiveCErrorNamesTheTypeUnderTheUnderlyingKey() async throws {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.attestResult = .failure(HostThrew())

        let swift: TapToPayError
        do {
            try await ttp.initialize()
            return XCTFail("expected initialize to fail")
        } catch let error as TapToPayError {
            swift = error
        }
        let bridged = swift.toPayabliNSError()

        XCTAssertEqual(bridged.domain, "com.payabli.ttp")
        XCTAssertEqual(bridged.code, swift.code)
        let cause = try XCTUnwrap(bridged.userInfo[NSUnderlyingErrorKey] as? NSError)
        XCTAssertTrue(cause.localizedDescription.hasSuffix("HostThrew"), cause.localizedDescription)
        XCTAssertFalse("\(bridged.userInfo)".contains("MESSAGE-SENTINEL"))
    }

    // MARK: - Telemetry

    func testAFailedInitializeNamesTheTypeOnce() async throws {
        let (ttp, _, attestation, transport) = try makeTTP()
        attestation.attestResult = .failure(HostThrew())

        _ = try? await ttp.initialize()
        await ttp.reports.sent()
        await ttp.session.telemetry.flush()

        let failed = await transport.batches.flatMap { $0 }.filter { $0.event == "ttp.initialize.failed" }
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed.first?.properties["failure_type"], "HostThrew")
        XCTAssertEqual(failed.first?.properties["error_number"], String(PayabliErrorType.unknown.number))
    }

    // MARK: - Fixtures

    private func assertConverted(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ call: () async throws -> Void
    ) async throws {
        do {
            try await call()
            XCTFail("expected the call to fail", file: file, line: line)
        } catch let error as TapToPayError {
            XCTAssertEqual(error.type, .unknown, file: file, line: line)
            XCTAssertEqual(error.reason, PayabliErrorType.unknown.message, file: file, line: line)
            XCTAssertNil(error.detail, file: file, line: line)
            let cause = try XCTUnwrap(error.underlying as? RedactedCause, file: file, line: line)
            XCTAssertEqual(cause.simpleTypeName, "HostThrew", file: file, line: line)
            XCTAssertFalse("\(error)".contains("MESSAGE-SENTINEL"), "the message crossed", file: file, line: line)
            XCTAssertFalse(error.localizedDescription.contains("MESSAGE-SENTINEL"), file: file, line: line)
        }
    }

    private func assertPassesThrough<Expected: Error>(
        _: Expected.Type,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ call: () async throws -> Void
    ) async throws {
        do {
            try await call()
            XCTFail("expected the call to fail", file: file, line: line)
        } catch {
            XCTAssertTrue(error is Expected, "got \(error)", file: file, line: line)
        }
    }

    private func makeTTP(tokenProvider: @escaping PayabliTokenRefresh = { "seed_token" }) throws -> (
        PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService, InMemoryTelemetryTransport
    ) {
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: tokenProvider)
        let provider = MockTapToPayProvider()
        let attestation = MockDeviceAttestationService()
        let transport = InMemoryTelemetryTransport()
        let ttp = PayabliTTP(
            config: config,
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession(),
            telemetry: transport
        )
        return (ttp, provider, attestation, transport)
    }

    /// Three terminals failing with `failure` after attesting: one signing the `/config` request, one configuring its
    /// reader and one preparing it.
    private func terminalsFailingEachSetupStage(with failure: Error) throws -> [PayabliTTP] {
        let (signing, _, signingAttestation, _) = try makeTTP()
        signingAttestation.assertionFailure = failure
        let (configuring, configureProvider, _, _) = try makeTTP()
        configureProvider.configureResult = .failure(failure)
        let (preparing, prepareProvider, _, _) = try makeTTP()
        prepareProvider.prepareReaderResult = .failure(failure)
        return [signing, configuring, preparing]
    }

    private func makeReadyTTP() async throws -> (
        PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService, InMemoryTelemetryTransport
    ) {
        let made = try makeTTP()
        try await made.0.initialize()
        return made
    }

    /// A terminal waiting on its activation code, the only state `activateDevice` sends from.
    private func makePendingTTP() async throws -> (
        PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService, InMemoryTelemetryTransport
    ) {
        let made = try makeTTP()
        made.2.pendingRegistration = "dev_e"
        _ = try? await made.0.initialize()
        XCTAssertEqual(made.0.sessionState, .pendingActivation(activationId: "dev_e"))
        return made
    }

    private static let handler: StubURLProtocol.Handler = { request in
        let path = request.url?.path ?? ""
        let body: [String: Any] = if path.contains("/MoneyIn/") {
            ["code": "A01", "data": ["paymentTransId": "TXN-1"]]
        } else {
            [
                "responseCode": 1,
                "isSuccess": true,
                "responseData": ["credentials": ["secretKey": "s", "apiKey": "a", "merchantId": "m", "terminalId": "t"]]
            ]
        }
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
            try JSONSerialization.data(withJSONObject: body)
        )
    }
}
