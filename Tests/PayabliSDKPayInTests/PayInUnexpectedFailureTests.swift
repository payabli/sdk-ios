@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import PayabliSDKTestUtils
import XCTest

/// Every public entry point hands the integrator the SDK's unknown failure for an error it does not
/// know, keeping cancellations and the SDK's own errors as they are.
@MainActor
final class PayInUnexpectedFailureTests: XCTestCase {
    private let recorder = InMemoryTelemetryTransport()
    private var telemetry: TelemetryClient?

    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    // MARK: - Every entry point

    func testACaptureConvertsAnErrorItDoesNotKnow() async throws {
        try await convertsThroughTheEntryPoint { _ = try await $0.capture(PayInFixture.request(cardOnly: true)) }
    }

    func testAnAuthorizeConvertsAnErrorItDoesNotKnow() async throws {
        try await convertsThroughTheEntryPoint { _ = try await $0.authorize(PayInFixture.request(cardOnly: true)) }
    }

    func testACaptureAuthorizedTransactionConvertsAnErrorItDoesNotKnow() async throws {
        try await convertsThroughTheEntryPoint {
            _ = try await $0.captureAuthorizedTransaction(
                PayabliPayInAuthorizedRequest(transId: "trans-1", paymentDetails: PayabliPayInPaymentDetails(totalAmount: 1))
            )
        }
    }

    func testAVoidConvertsAnErrorItDoesNotKnow() async throws {
        try await convertsThroughTheEntryPoint { _ = try await $0.voidTransaction("trans-1") }
    }

    func testAReadConvertsAnErrorItDoesNotKnow() async throws {
        try await convertsThroughTheEntryPoint { _ = try await $0.readTransaction("trans-1") }
    }

    func testACardStoreConvertsAnErrorItDoesNotKnow() async throws {
        try await convertsThroughTheEntryPoint {
            _ = try await $0.storeMethod(PayabliPayInStoreRequest(instrument: .card(Self.card), options: PayabliPayInStoreOptions()))
        }
    }

    func testABankAccountStoreConvertsAnErrorItDoesNotKnow() async throws {
        try await convertsThroughTheEntryPoint {
            _ = try await $0.storeMethod(PayabliPayInStoreRequest(
                instrument: .bankAccount(Self.bankAccount),
                options: PayabliPayInStoreOptions()
            ))
        }
    }

    func testAFormCaptureConvertsAnErrorItDoesNotKnow() async throws {
        let request = PayInFixture.request(cardOnly: true)
        try await convertsThroughTheEntryPoint {
            _ = try await $0.submitConfigured(request, for: .capture(request.options), origin: .form)
        }
    }

    // MARK: - What passes through

    func testACancellationPassesThroughTheEntryPointUnconverted() async {
        let flow = makeFlow(RecordingIdempotencyTransport(failure: CancellationError()))

        let told = await PayInFixture.failure { _ = try await flow.readTransaction("trans-1") }

        XCTAssertTrue(told is CancellationError)
        XCTAssertNil(told as? PayabliGenericError)
    }

    func testAPlatformCancellationReachesTheHostAsACancellation() async {
        let flow = makeFlow(RecordingIdempotencyTransport(failure: URLError(.cancelled)))

        let told = await PayInFixture.failure { _ = try await flow.readTransaction("trans-1") }

        XCTAssertTrue(told is CancellationError, "\(String(describing: told))")
    }

    func testAPlatformCancellationOfASaveReachesTheHostAsACancellation() async {
        let flow = makeFlow(RecordingIdempotencyTransport(failure: URLError(.cancelled)))

        let told = await PayInFixture.failure {
            _ = try await flow.storeMethod(PayabliPayInStoreRequest(instrument: .card(Self.card), options: PayabliPayInStoreOptions()))
        }

        XCTAssertTrue(told is CancellationError, "\(String(describing: told))")
    }

    func testAnErrorTheSdkAlreadyClassifiedPassesThroughUnconverted() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(
            failure: PayabliGenericError(type: .networkError, reason: "offline")
        ))

        let told = await PayInFixture.failure { _ = try await flow.readTransaction("trans-1") }

        let passed = try XCTUnwrap(told as? PayabliGenericError)
        XCTAssertEqual(passed.type, .networkError)
        XCTAssertEqual(passed.reason, "offline")
    }

    // MARK: - The money-open wrap is untouched

    func testAnErrorAfterTheSendMarkKeepsTheMoneyOpenWrap() async {
        let flow = makeFlow(RecordingIdempotencyTransport(failure: HostThrew()))

        let told = await PayInFixture.failure { _ = try await flow.capture(PayInFixture.request(cardOnly: true)) }

        let interruption = PayInFixture.interruption(told)
        XCTAssertEqual(interruption?.type, .unknown)
        XCTAssertEqual(interruption?.causeType, String(reflecting: type(of: HostThrew())))
    }

    // MARK: - Reporting

    func testAConvertedFailureIsReportedOnceByTheEntryPointThatConvertedIt() async throws {
        let flow = makeFlow(ForeignErrorTransport(failure: HostThrew()))

        _ = await PayInFixture.failure { _ = try await flow.capture(PayInFixture.request(cardOnly: true)) }

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.capture.completed")
        XCTAssertEqual(
            Set(event.properties.keys),
            ["outcome", "origin", "method", "duration_ms", "code", "error_number", "failure_type"]
        )
        XCTAssertEqual(event.properties["outcome"], "failed")
        XCTAssertEqual(event.properties["code"], "UNKNOWN")
        XCTAssertEqual(event.properties["error_number"], String(PayabliErrorType.unknown.number))
        XCTAssertEqual(event.properties["failure_type"], "HostThrew")
        XCTAssertNotNil(Int(event.properties["duration_ms"] ?? ""))
    }

    func testAConvertedFailureOnAVoidReportsNoMethod() async throws {
        let flow = makeFlow(ForeignErrorTransport(failure: HostThrew()))

        _ = await PayInFixture.failure { _ = try await flow.voidTransaction("trans-1") }

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.void.completed")
        XCTAssertEqual(
            Set(event.properties.keys),
            ["outcome", "origin", "duration_ms", "code", "error_number", "failure_type"]
        )
        XCTAssertEqual(event.properties["failure_type"], "HostThrew")
    }

    // MARK: - The form

    func testAFormSubmissionConvertsAnErrorItDoesNotKnow() async throws {
        let flow = makeFlow(ForeignErrorTransport(failure: HostThrew()))
        let viewModel = PayabliPayInViewModel(
            component: flow,
            operation: .storePaymentMethod(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "12/30"
        viewModel.cardCvv = "123"
        viewModel.cardholderName = "Jane"
        viewModel.cardZip = "12345"

        let told = await PayInFixture.failure { _ = try await viewModel.submit() }

        let converted = try XCTUnwrap(told as? PayabliGenericError)
        XCTAssertEqual(converted.type, .unknown)
        XCTAssertEqual(converted.reason, PayabliErrorType.unknown.message)
        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.storeMethod.completed")
        XCTAssertEqual(event.properties["origin"], "form")
        XCTAssertEqual(event.properties["outcome"], "failed")
    }

    // MARK: - Helpers

    private func convertsThroughTheEntryPoint(
        _ run: (PayabliPayIn) async throws -> Void
    ) async throws {
        let flow = makeFlow(ForeignErrorTransport(failure: HostThrew()))

        let told = await PayInFixture.failure { try await run(flow) }

        let converted = try XCTUnwrap(told as? PayabliGenericError)
        XCTAssertEqual(converted.type, .unknown)
        XCTAssertEqual(converted.reason, PayabliErrorType.unknown.message)
        XCTAssertNil(converted.detail)
        let redacted = try XCTUnwrap(converted.underlying as? RedactedCause)
        XCTAssertEqual(redacted.originalType, String(reflecting: type(of: HostThrew())))
        XCTAssertFalse(converted.reason.contains(HostThrew().message))
    }

    private func makeFlow(_ transport: any PayabliTransport) -> PayabliPayIn {
        let telemetry = TelemetryClient(
            configuration: .init(entry: "entry", environment: "sandbox"),
            transport: recorder,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) },
            lifecycle: NoBackgrounding(),
            deviceId: { nil },
            queued: []
        )
        self.telemetry = telemetry
        return PayabliPayIn(
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            telemetry: telemetry
        )
    }

    /// The one event the flow reported; fails unless there is exactly one.
    private func onlyEvent(of flow: PayabliPayIn, file: StaticString = #filePath, line: UInt = #line) async throws
        -> TelemetryEvent
    {
        let reports = try XCTUnwrap(flow.reports, file: file, line: line)
        await reports.sent()
        await telemetry?.flush()
        let events = await recorder.batches.flatMap { $0 }
        XCTAssertEqual(events.count, 1, "\(events.map(\.event))", file: file, line: line)
        return try XCTUnwrap(events.first, file: file, line: line)
    }

    private static let card = PayabliPayInCardData(
        cardNumber: "4111111111111111",
        expiryMonth: 12,
        expiryYear: 2030,
        securityCode: "123",
        holderName: "Jane",
        postalCode: "12345"
    )

    private static let bankAccount = PayabliPayInBankAccountData(
        accountNumber: "1111111111",
        routingNumber: "123456780",
        accountType: .checking,
        holderName: "Jane"
    )
}

/// An app that never leaves the foreground.
private struct NoBackgrounding: AppLifecycle {
    func backgroundings() -> AsyncStream<BackgroundWindow> {
        AsyncStream { _ in }
    }
}
