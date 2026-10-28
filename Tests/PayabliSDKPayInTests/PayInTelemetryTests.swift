@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// Every operation reports one `payin.*.completed` event with the catalog's properties, and nothing about the
/// instrument or the payer.
@MainActor
final class PayInTelemetryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    private let recorder = RecordingTelemetryTransport()
    private var telemetry: TelemetryClient?

    // MARK: - Direct members

    func testAnApprovedCaptureReportsItsOutcomeOriginMethodAndDuration() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: PayInFixture.approved))

        _ = try await flow.capture(PayInFixture.request(cardOnly: true))

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.capture.completed")
        XCTAssertEqual(Set(event.properties.keys), ["outcome", "origin", "method", "duration_ms"])
        XCTAssertEqual(event.properties["outcome"], "approved")
        XCTAssertEqual(event.properties["origin"], "direct")
        XCTAssertEqual(event.properties["method"], "card")
        XCTAssertNotNil(Int(event.properties["duration_ms"] ?? ""))
    }

    func testADeclinedCaptureCarriesTheCodeTheCallerWasTold() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: PayInFixture.declined))

        let told = await PayInFixture.failure { _ = try await flow.capture(PayInFixture.request(cardOnly: true)) }

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.capture.completed")
        XCTAssertEqual(
            Set(event.properties.keys),
            ["outcome", "origin", "method", "duration_ms", "code", "error_number", "failure_type"]
        )
        XCTAssertEqual(event.properties["outcome"], "declined")
        XCTAssertEqual(event.properties["code"], "PAYMENT_DECLINED")
        XCTAssertEqual(event.properties["error_number"], String((told as? any PayabliError)?.code ?? -1))
        XCTAssertEqual(event.properties["failure_type"], "PayabliPayInError")
    }

    func testAnAuthorizationReportsItsOwnEvent() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: PayInFixture.approved))

        _ = try await flow.authorize(PayInFixture.request(cardOnly: true))

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.authorize.completed")
        XCTAssertEqual(event.properties["method"], "card")
    }

    func testAStoredMethodReportsTheKindItStores() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: PayInFixture.approved))

        _ = try await flow.capture(PayInFixture.request())

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.properties["method"], "card")
    }

    func testCashAndACloudDeviceReportNoMethod() {
        XCTAssertNil(PayInReports.method(of: .cash))
        XCTAssertNil(PayInReports.method(of: .cloudDevice(PayabliPayInPaymentMethod.CloudDevice(device: "device-1"))))
    }

    func testABankAccountAndACheckReportTheirKind() {
        XCTAssertEqual(PayInReports.method(of: .bankAccount(PayabliPayInPaymentMethod.BankAccount(
            data: PayabliPayInBankAccountData(
                accountNumber: "1111111111",
                accountType: .checking,
                holderName: "Jane",
                routingNumber: "123456780"
            )
        ))), "bank")
        XCTAssertEqual(PayInReports.method(of: .check(PayabliPayInPaymentMethod.Check(holderName: "Jane"))), "check")
    }

    func testAConvertedTypeIsNamedAsItsOwnSourceSpellsIt() {
        let interrupted = PayabliPayInError.submissionInterrupted(
            type: .unknown,
            causeType: "Module.Wrap<Module.Inner>",
            paymentTransId: nil,
            paymentReference: nil
        )

        XCTAssertEqual(PayInReports.failureType(of: interrupted), "Wrap<Inner>")
    }

    func testCapturingAnAuthorizationIsReportedAsACaptureWithNoMethod() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: PayInFixture.approved))

        _ = try await flow.captureAuthorizedTransaction(
            PayabliPayInAuthorizedRequest(transId: "trans-1", paymentDetails: PayabliPayInPaymentDetails(totalAmount: 1))
        )

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.capture.completed")
        XCTAssertNil(event.properties["method"])
    }

    func testAVoidReportsNoMethod() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: PayInFixture.approved))

        _ = try await flow.voidTransaction("trans-1")

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.void.completed")
        XCTAssertEqual(Set(event.properties.keys), ["outcome", "origin", "duration_ms"])
    }

    func testAReadReportsNoIdentifierAndNoStatus() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: Self.transactionRecord))

        _ = try await flow.readTransaction("101-abc")

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.read.completed")
        XCTAssertEqual(Set(event.properties.keys), ["outcome", "origin", "duration_ms"])
        XCTAssertFalse(event.properties.values.contains("101-abc"))
    }

    func testStoringACardReportsTheStoreEvent() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: Self.stored))

        _ = try await flow.addCard(Self.card)

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.storeMethod.completed")
        XCTAssertEqual(event.properties["outcome"], "approved")
        XCTAssertEqual(event.properties["method"], "card")
    }

    // MARK: - Outcomes

    func testARefusalBeforeSendingCarriesNoDuration() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: PayInFixture.approved))
        let request = PayabliPayInRequest(
            paymentMethod: PayInFixture.request(cardOnly: true).paymentMethod,
            options: PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34),
                paymentReference: "   "
            )
        )

        _ = await PayInFixture.failure { _ = try await flow.capture(request) }

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.properties["outcome"], "refused_locally")
        XCTAssertEqual(event.properties["code"], "VALIDATION_ERROR")
        XCTAssertNil(event.properties["duration_ms"])
    }

    func testARetryUnderAHeldKeyRefusedBeforeSendingIsRefusedLocally() async throws {
        let transport = ScriptedTransport()
        transport.script = [.lost]
        let flow = makeFlow(transport)

        _ = await PayInFixture.failure { _ = try await flow.capture(Self.heldKeyRequest(.newPayment, cvv: "123")) }
        let told = await PayInFixture.failure { _ = try await flow.capture(Self.heldKeyRequest(.retry, cvv: "")) }

        let reports = try XCTUnwrap(flow.reports)
        await reports.sent()
        await telemetry?.flush()
        let events = await recorder.events
        XCTAssertEqual(events.count, 2, "\(events.map(\.event))")
        let refused = try XCTUnwrap(events.last)
        XCTAssertNotNil(PayInFixture.interruption(told), "the caller is no longer told the payment is open: \(told)")
        XCTAssertEqual(refused.properties["outcome"], "refused_locally")
        XCTAssertNil(refused.properties["duration_ms"])
        XCTAssertEqual(transport.sentKeys.count, 1, "the refused retry reached the transport")
    }

    func testAFieldTheServiceRejectedIsRefusedNotRefusedLocally() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: Data(#"{"responseText":"Bad"}"#.utf8), status: 400))

        _ = await PayInFixture.failure { _ = try await flow.capture(PayInFixture.request(cardOnly: true)) }

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.properties["outcome"], "refused")
        XCTAssertNotNil(event.properties["duration_ms"])
    }

    func testACancelledSendIsInterrupted() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(failure: CancellationError()))

        let told = await PayInFixture.failure { _ = try await flow.capture(PayInFixture.request(cardOnly: true)) }

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.properties["outcome"], "interrupted")
        XCTAssertEqual(event.properties["code"], (told as? any PayabliError)?.type.rawValue, "the code the caller was told")
        XCTAssertNotNil(event.properties["error_number"])
        XCTAssertEqual(event.properties["failure_type"], "CancellationError")
    }

    func testAFailureNothingClassifiedIsFailed() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(
            failure: PayabliGenericError(type: .networkError, reason: "offline")
        ))

        _ = await PayInFixture.failure { _ = try await flow.capture(PayInFixture.request(cardOnly: true)) }

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.properties["outcome"], "failed")
        XCTAssertEqual(event.properties["failure_type"], "PayabliGenericError")
    }

    // MARK: - The form

    func testTheFormReportsItsSubmissionsAsTheForm() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: Self.stored))
        let viewModel = PayabliPayInViewModel(
            component: flow,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "12/30"
        viewModel.cardCvv = "123"
        viewModel.cardholderName = "Jane"
        viewModel.cardZip = "12345"

        _ = try await viewModel.submit()

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.storeMethod.completed")
        XCTAssertEqual(event.properties["origin"], "form")
        XCTAssertEqual(event.properties["outcome"], "approved")
    }

    func testAFormThatCannotSubmitIsReportedOnceAsRefusedLocally() async throws {
        let transport = RecordingIdempotencyTransport(body: Self.stored)
        let flow = makeFlow(transport)
        let viewModel = PayabliPayInViewModel(
            component: flow,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )

        _ = await PayInFixture.failure { _ = try await viewModel.submit() }

        XCTAssertEqual(transport.count, 0, "nothing was sent")
        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.storeMethod.completed")
        XCTAssertEqual(event.properties["origin"], "form")
        XCTAssertEqual(event.properties["outcome"], "refused_locally")
        XCTAssertEqual(event.properties["method"], "card")
        XCTAssertNil(event.properties["duration_ms"])
    }

    func testAFormRefusalTheFlowNeverSeesIsReportedByTheForm() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = makeFlow(transport, operation: .capture)
        let viewModel = PayabliPayInViewModel(
            component: flow,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "12/30"
        viewModel.cardCvv = "123"
        viewModel.cardholderName = "Jane"
        viewModel.cardZip = "12345"

        _ = await PayInFixture.failure { _ = try await viewModel.submit() }

        XCTAssertEqual(transport.count, 0, "no request configuration, so nothing was sent")
        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.capture.completed")
        XCTAssertEqual(event.properties["origin"], "form")
        XCTAssertEqual(event.properties["outcome"], "refused_locally")
    }

    func testAFormAmountRefusalIsReportedOnceByTheFlow() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = makeFlow(transport, operation: .capture)
        flow.configure(requestConfiguration: PayabliPayInRequestConfiguration(
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 1.00, serviceFee: 1.00, currency: "USD")
        ))
        let viewModel = PayabliPayInViewModel(
            component: flow,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "12/30"
        viewModel.cardCvv = "123"
        viewModel.cardholderName = "Jane"
        viewModel.cardZip = "12345"

        _ = await PayInFixture.failure { _ = try await viewModel.submit() }

        XCTAssertEqual(transport.count, 0, "a fee equal to the total is refused before sending")
        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.event, "payin.capture.completed")
        XCTAssertEqual(event.properties["origin"], "form")
        XCTAssertEqual(event.properties["outcome"], "refused_locally")
    }

    func testAFormSubmissionTheServiceRefusesIsReportedOnceByTheFlow() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: Data(#"{"responseText":"Bad"}"#.utf8), status: 400))
        let viewModel = PayabliPayInViewModel(
            component: flow,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "12/30"
        viewModel.cardCvv = "123"
        viewModel.cardholderName = "Jane"
        viewModel.cardZip = "12345"

        _ = await PayInFixture.failure { _ = try await viewModel.submit() }

        let event = try await onlyEvent(of: flow)
        XCTAssertEqual(event.properties["origin"], "form")
        XCTAssertEqual(event.properties["outcome"], "refused")
    }

    func testASecondFormSubmissionWhileOneRunsIsCountedByItsOutcomeAlone() async throws {
        let transport = GatedTransport(RecordingIdempotencyTransport(body: Self.stored))
        let flow = makeFlow(transport)
        let viewModel = PayabliPayInViewModel(
            component: flow,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], defaultMethod: .card)
        )
        viewModel.cardNumber = "4111111111111111"
        viewModel.cardExpiration = "12/30"
        viewModel.cardCvv = "123"
        viewModel.cardholderName = "Jane"
        viewModel.cardZip = "12345"

        let first = Task { try await viewModel.submit() }
        await transport.firstArrival()
        _ = try? await viewModel.submit()
        transport.open()
        _ = try? await first.value

        let reports = try XCTUnwrap(flow.reports)
        await reports.sent()
        await telemetry?.flush()
        let refused = await recorder.events.filter { $0.properties["outcome"] == "refused_locally" }
        XCTAssertEqual(refused.count, 1)
        XCTAssertEqual(refused.first.map { Set($0.properties.keys) }, ["outcome", "origin", "method"])
    }

    // MARK: - Privacy

    func testNoReportCarriesInstrumentOrPayerData() async throws {
        let flow = makeFlow(RecordingIdempotencyTransport(body: PayInFixture.declined))

        _ = await PayInFixture.failure { _ = try await flow.capture(PayInFixture.request(cardOnly: true)) }

        let event = try await onlyEvent(of: flow)
        let values = event.properties.values.joined(separator: " ")
        for forbidden in ["4111", "John", "Cassian", "999", "12345", "02/27"] {
            XCTAssertFalse(values.contains(forbidden), forbidden)
        }
    }

    // MARK: - Helpers

    private func makeFlow(
        _ transport: any PayabliTransport,
        operation: PayabliPayInOperation = .storePaymentMethod
    ) -> PayabliPayIn {
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
            operation: operation,
            telemetry: telemetry
        )
    }

    /// The one event the flow reported, failing rather than reading past the end.
    private func onlyEvent(of flow: PayabliPayIn, file: StaticString = #filePath, line: UInt = #line) async throws
        -> TelemetryEvent
    {
        let reports = try XCTUnwrap(flow.reports, file: file, line: line)
        await reports.sent()
        await telemetry?.flush()
        let events = await recorder.events
        XCTAssertEqual(events.count, 1, "\(events.map(\.event))", file: file, line: line)
        return try XCTUnwrap(events.first, file: file, line: line)
    }

    /// A card capture under reference `p1`, so a lost first attempt holds a key that a retry takes.
    private static func heldKeyRequest(_ attempt: PayabliAttempt, cvv: String) -> PayabliPayInRequest {
        PayabliPayInRequest(
            paymentMethod: .card(PayabliPayInPaymentMethod.Card(data: PayabliPayInCardData(
                cardNumber: "4111111111111111",
                expiration: "12/30",
                cardholderName: "Jane",
                cvv: cvv,
                billingZip: "12345"
            ))),
            options: PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34),
                paymentReference: "p1",
                attempt: attempt
            )
        )
    }

    private static let card = PayabliPayInCardData(
        cardNumber: "4111111111111111",
        expiration: "12/30",
        cardholderName: "Jane",
        cvv: "123",
        billingZip: "12345"
    )

    private static let stored = Data("""
    {"responseText":"Success","isSuccess":true,"responseData":{"referenceId":"stored-123","resultCode":1,\
    "resultText":"Approved","methodReferenceId":"stored-123"}}
    """.utf8)

    private static let transactionRecord = Data("""
    {"PaymentTransId": "101-abc", "TransStatus": 5, "Method": "card", "TotalAmount": 1.10}
    """.utf8)
}

/// Records every event the client sends.
private actor RecordingTelemetryTransport: TelemetryTransport {
    private(set) var events: [TelemetryEvent] = []

    func send(_ batch: [TelemetryEvent]) async -> TelemetrySendOutcome {
        events += batch
        return .delivered
    }
}

/// Holds every request until opened, so a test can act while one is in flight.
private final class GatedTransport: PayabliTransport, @unchecked Sendable {
    private let inner: any PayabliTransport
    private let lock = NSLock()
    private var isOpen = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var hasArrived = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

    init(_ inner: any PayabliTransport) {
        self.inner = inner
    }

    /// Returns once the first request has reached the transport.
    func firstArrival() async {
        await withCheckedContinuation { continuation in
            let arrived = lock.withLock {
                if !hasArrived {
                    arrivalWaiters.append(continuation)
                }
                return hasArrived
            }
            if arrived {
                continuation.resume()
            }
        }
    }

    /// Lets every held request, and every later one, through.
    func open() {
        let waiting = lock.withLock {
            isOpen = true
            defer { held = [] }
            return held
        }
        waiting.forEach { $0.resume() }
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        await withCheckedContinuation { continuation in
            let (passes, waiters) = lock.withLock {
                hasArrived = true
                defer { arrivalWaiters = [] }
                if !isOpen {
                    held.append(continuation)
                }
                return (isOpen, arrivalWaiters)
            }
            waiters.forEach { $0.resume() }
            if passes {
                continuation.resume()
            }
        }
        return try await inner.perform(request)
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        let response = try await perform(request)
        try mapPayabliHTTPError(response: response)
        return try decodePayabliV2Envelope(T.self, from: response)
    }
}

/// An app that never leaves the foreground.
private struct NoBackgrounding: AppLifecycle {
    func backgroundings() -> AsyncStream<BackgroundWindow> {
        AsyncStream { _ in }
    }
}
