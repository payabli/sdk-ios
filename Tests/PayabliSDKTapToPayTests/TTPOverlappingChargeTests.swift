import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// A charge made while another runs anywhere in the process: what it is told, and what it leaves behind.
@available(iOS 16.7, *)
@MainActor
final class TTPOverlappingChargeTests: XCTestCase {
    private static let wire = Wire()
    private let clock = ManualChargeClock()
    private lazy var store = ChargeKeyStore(now: { [clock] in clock.now })

    override func tearDown() {
        StubURLProtocol.handler = nil
        Self.wire.reset()
        super.tearDown()
    }

    // MARK: - What the overlapping charge is told

    /// Two terminals, so the test fails if the gate is held per `PayabliTTP` rather than per process.
    func testASecondTerminalOnTheSameEntryPointIsRefusedAndReservesNothing() async throws {
        let (running, provider) = try await makeReadyTTP()
        let (other, otherProvider) = try await makeReadyTTP()
        let during = Overlap()
        provider.whileReading = { [weak other] in
            guard let other else { return }
            during.refusal = await Self.failure { try await other.charge(paymentDetails: Self.sale) }
        }

        _ = try await running.charge(paymentDetails: Self.sale)

        XCTAssertEqual(during.refusal?.type, .terminalNotReady)
        XCTAssertEqual(during.refusal?.capture, .notCharged)
        XCTAssertEqual(Self.wire.keys.count, 1, "the refused charge sent an opening")
        XCTAssertEqual(otherProvider.startReadingCalls, 0)
        XCTAssertNil(store.heldRetry(entry: "e", environment: .sandbox, description: description(Self.sale)))
        XCTAssertEqual(other.sessionState, .ready)
    }

    func testARetryWhoseKeyIsBeingSentIsRefusedAsOpenThenResendsItOnceThatChargeEndsUnknown() async throws {
        let (running, provider) = try await makeReadyTTP(outcome: .indeterminate)
        let (other, otherProvider) = try await makeReadyTTP()
        let during = Overlap()
        provider.whileReading = { [weak other] in
            guard let other else { return }
            during.refusal = await Self.failure { try await other.charge(paymentDetails: Self.sale, attempt: .retry) }
        }

        _ = await Self.failure { try await running.charge(paymentDetails: Self.sale) }

        XCTAssertEqual(during.refusal?.type, .paymentReferenceOpen)
        XCTAssertEqual(during.refusal?.capture, .unknown)
        XCTAssertEqual(Self.wire.keys.count, 1, "the refused retry sent its key")
        XCTAssertEqual(otherProvider.startReadingCalls, 0)

        provider.whileReading = nil
        _ = try await other.charge(paymentDetails: Self.sale, attempt: .retry)

        XCTAssertEqual(Self.wire.keys.count, 2)
        XCTAssertEqual(Self.wire.keys[1], Self.wire.keys[0], "the retry did not resend the unknown charge's key")
    }

    func testAChargeOnAnotherEntryPointIsRefusedAndReadsOnlyItsOwnEntryPoint() async throws {
        let (running, provider) = try await makeReadyTTP()
        let (other, otherProvider) = try await makeReadyTTP(entryPoint: "other")
        let during = Overlap()
        provider.whileReading = { [weak other] in
            guard let other else { return }
            during.refusal = await Self.failure { try await other.charge(paymentDetails: Self.sale) }
            // The running charge's sale, on an entry point where nothing of its own is held.
            during.retryRefusal = await Self.failure {
                try await other.charge(paymentDetails: Self.sale, attempt: .retry)
            }
        }

        _ = try await running.charge(paymentDetails: Self.sale)

        XCTAssertEqual(during.refusal?.type, .terminalNotReady)
        XCTAssertEqual(during.refusal?.capture, .notCharged)
        XCTAssertEqual(during.retryRefusal?.type, .terminalNotReady)
        XCTAssertEqual(during.retryRefusal?.capture, .notCharged)
        XCTAssertEqual(Self.wire.keys.count, 1, "a refused charge sent an opening")
        XCTAssertEqual(otherProvider.startReadingCalls, 0)
        XCTAssertNil(store.heldRetry(entry: "other", environment: .sandbox, description: description(Self.sale)))
    }

    // MARK: - The capture a refused retry reports

    func testARetryOfTheRunningSaleIsUnknownAfterItsKeyWasSettled() async throws {
        let (running, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await Self.failure { try await running.charge(paymentDetails: Self.sale) }
        provider.readingResult = Self.read(.approved)
        let (other, _) = try await makeReadyTTP()
        let during = Overlap()
        provider.whileReading = { [weak self, weak other] in
            guard let self, let other else { return }
            // The running charge settles its own key before the refusal reads the store.
            store.settle(entry: "e", environment: .sandbox, key: Self.wire.keys[1])
            during.refusal = await Self.failure {
                try await other.charge(paymentDetails: Self.otherSale, attempt: .retry)
            }
        }

        _ = try await running.charge(paymentDetails: Self.otherSale)

        XCTAssertEqual(during.refusal?.type, .terminalNotReady)
        XCTAssertEqual(during.refusal?.capture, .unknown)
    }

    func testARetryOfAnOlderHeldSaleIsUnknownAndItsKeyStays() async throws {
        let (running, provider) = try await makeReadyTTP(outcome: .indeterminate)
        _ = await Self.failure { try await running.charge(paymentDetails: Self.sale) }
        provider.readingResult = Self.read(.approved)
        let (other, _) = try await makeReadyTTP()
        let during = Overlap()
        provider.whileReading = { [weak other] in
            guard let other else { return }
            during.refusal = await Self.failure { try await other.charge(paymentDetails: Self.sale, attempt: .retry) }
        }

        _ = try await running.charge(paymentDetails: Self.otherSale)

        XCTAssertEqual(during.refusal?.capture, .unknown)
        provider.whileReading = nil
        _ = try await other.charge(paymentDetails: Self.sale, attempt: .retry)
        XCTAssertEqual(Self.wire.keys.count, 3, "the refused retry sent its key")
        XCTAssertEqual(Self.wire.keys[2], Self.wire.keys[0], "the older sale's key was not kept")
    }

    func testWithNothingHeldARetryIsUnknownOnlyWhenItDescribesTheRunningSale() async throws {
        let (running, provider) = try await makeReadyTTP()
        let (other, _) = try await makeReadyTTP()
        let during = Overlap()
        provider.whileReading = { [weak self, weak other] in
            guard let self, let other else { return }
            store.settle(entry: "e", environment: .sandbox, key: Self.wire.keys[0])
            during.refusal = await Self.failure { try await other.charge(paymentDetails: Self.sale, attempt: .retry) }
            during.retryRefusal = await Self.failure {
                try await other.charge(paymentDetails: Self.otherSale, attempt: .retry)
            }
        }

        _ = try await running.charge(paymentDetails: Self.sale)

        XCTAssertEqual(during.refusal?.type, .terminalNotReady)
        XCTAssertEqual(during.refusal?.capture, .unknown)
        XCTAssertEqual(during.retryRefusal?.type, .terminalNotReady)
        XCTAssertEqual(during.retryRefusal?.capture, .notCharged)
    }

    // MARK: - A retry refused on a retired terminal

    func testARetryOfAHeldSaleOnARetiredTerminalIsUnknownAndItsKeyStays() async throws {
        let live = LiveFlag()
        let (retired, _) = try await makeReadyTTP(outcome: .indeterminate, live: live)
        _ = await Self.failure { try await retired.charge(paymentDetails: Self.sale) }
        live.value = false

        let retry = await Self.failure { try await retired.charge(paymentDetails: Self.sale, attempt: .retry) }
        let newPayment = await Self.failure { try await retired.charge(paymentDetails: Self.sale) }

        XCTAssertEqual(retry?.type, .sessionNotInitialized)
        XCTAssertEqual(retry?.capture, .unknown)
        XCTAssertEqual(newPayment?.type, .sessionNotInitialized)
        XCTAssertEqual(newPayment?.capture, .notCharged, "a new payment describes no held sale")
        XCTAssertEqual(Self.wire.keys.count, 1, "the retired terminal sent an opening")
        let (other, _) = try await makeReadyTTP()
        _ = try await other.charge(paymentDetails: Self.sale, attempt: .retry)
        XCTAssertEqual(Self.wire.keys[1], Self.wire.keys[0], "the held sale's key was not kept")
    }

    /// The session is replaced after the retry claims the gate, so the refusal comes from inside it.
    func testARetryRetiredAfterItClaimsTheGateIsUnknownAndItsKeyStays() async throws {
        let live = LiveFlag()
        let (retired, _) = try await makeReadyTTP(outcome: .indeterminate, live: live)
        _ = await Self.failure { try await retired.charge(paymentDetails: Self.sale) }
        live.retire(after: 1)

        let retry = await Self.failure { try await retired.charge(paymentDetails: Self.sale, attempt: .retry) }

        XCTAssertEqual(retry?.type, .sessionNotInitialized)
        XCTAssertEqual(retry?.capture, .unknown)
        XCTAssertEqual(Self.wire.keys.count, 1, "the retired terminal sent an opening")
        let (other, _) = try await makeReadyTTP()
        _ = try await other.charge(paymentDetails: Self.sale, attempt: .retry)
        XCTAssertEqual(Self.wire.keys[1], Self.wire.keys[0], "the held sale's key was not kept")
    }

    func testOnARetiredTerminalARetryIsUnknownOnlyWhenItDescribesTheSaleRunningOnItsEntryPoint() async throws {
        let live = LiveFlag()
        let (retired, _) = try await makeReadyTTP(live: live)
        let (running, provider) = try await makeReadyTTP()
        live.value = false
        let during = Overlap()
        provider.whileReading = { [weak retired] in
            guard let retired else { return }
            during.refusal = await Self.failure {
                try await retired.charge(paymentDetails: Self.sale, attempt: .retry)
            }
            during.retryRefusal = await Self.failure {
                try await retired.charge(paymentDetails: Self.otherSale, attempt: .retry)
            }
        }

        _ = try await running.charge(paymentDetails: Self.sale)

        XCTAssertEqual(during.refusal?.type, .sessionNotInitialized)
        XCTAssertEqual(during.refusal?.capture, .unknown)
        XCTAssertEqual(during.retryRefusal?.type, .sessionNotInitialized)
        XCTAssertEqual(during.retryRefusal?.capture, .notCharged)
        XCTAssertEqual(Self.wire.keys.count, 1, "the retired terminal sent an opening")
    }

    // MARK: - The gate is released however a charge ends

    func testAnAnsweredChargeReleasesTheGate() async throws {
        let (ended, _) = try await makeReadyTTP()
        _ = try await ended.charge(paymentDetails: Self.sale)

        try await assertTheNextChargeIsAdmitted()
    }

    func testAnUnknownChargeReleasesTheGate() async throws {
        let (ended, _) = try await makeReadyTTP(outcome: .indeterminate)
        let unknown = await Self.failure { try await ended.charge(paymentDetails: Self.sale) }
        XCTAssertEqual(unknown?.capture, .unknown)

        try await assertTheNextChargeIsAdmitted()
    }

    func testAChargeRefusedBeforeSendingReleasesTheGate() async throws {
        let (ended, provider) = try await makeReadyTTP()
        Self.wire.initiateStatus = 400
        let refused = await Self.failure { try await ended.charge(paymentDetails: Self.sale) }
        XCTAssertEqual(provider.startReadingCalls, 0)
        XCTAssertEqual(refused?.capture, .notCharged)
        Self.wire.initiateStatus = 200

        try await assertTheNextChargeIsAdmitted()
    }

    func testACancelledChargeReleasesTheGate() async throws {
        let (ended, provider) = try await makeReadyTTP()
        let charging = Task { @MainActor in try await ended.charge(paymentDetails: Self.sale) }
        provider.whileReading = { charging.cancel() }
        _ = try? await charging.value
        XCTAssertTrue(charging.isCancelled)
        provider.whileReading = nil

        try await assertTheNextChargeIsAdmitted()
    }

    // MARK: - Helpers

    private static let sale = PayabliTTPPaymentDetails(amount: 1, currency: "USD")
    private static let otherSale = PayabliTTPPaymentDetails(amount: 2, currency: "USD")

    /// Whether a terminal's session is still the installed one, as a test sets it.
    private final class LiveFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = true
        private var readsLeft: Int?

        var value: Bool {
            get {
                lock.withLock {
                    if let left = readsLeft {
                        stored = left > 0
                        readsLeft = left - 1
                    }
                    return stored
                }
            }
            set { lock.withLock { stored = newValue } }
        }

        /// Answers live for the next `reads` reads, then retired.
        ///
        /// - Parameter reads: how many reads still find the session installed.
        func retire(after reads: Int) {
            lock.withLock { readsLeft = reads }
        }
    }

    private final class Overlap {
        var refusal: TapToPayError?
        var retryRefusal: TapToPayError?
    }

    /// A charge on another terminal reads a card, so nothing still holds the gate.
    private func assertTheNextChargeIsAdmitted(file: StaticString = #filePath, line: UInt = #line) async throws {
        let (next, provider) = try await makeReadyTTP()
        _ = try await next.charge(paymentDetails: Self.sale)
        XCTAssertEqual(provider.startReadingCalls, 1, "the gate was still held", file: file, line: line)
    }

    private func description(_ details: PayabliTTPPaymentDetails) -> ChargeDescription {
        ChargeDescription(paymentDetails: details, invoice: PayabliTTPInvoiceData())
    }

    private static func read(_ outcome: CardReadOutcome) -> Result<CardReadResult, Error> {
        .success(CardReadResult(provider: "mock", encryptedPayload: Data(), outcome: outcome))
    }

    /// A ready terminal sharing this test's key store, so two of them see each other's keys.
    private func makeReadyTTP(
        entryPoint: String = "e",
        outcome: CardReadOutcome = .approved,
        live: LiveFlag = LiveFlag()
    ) async throws -> (PayabliTTP, MockTapToPayProvider) {
        StubURLProtocol.handler = Self.stubHandler
        let provider = MockTapToPayProvider()
        provider.readingResult = Self.read(outcome)
        let ttp = PayabliTTP(
            config: try PayabliConfig(entryPoint: entryPoint, environment: .sandbox, tokenProvider: { "seed_token" }),
            provider: provider,
            attestation: MockDeviceAttestationService(),
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession(),
            isLive: { live.value },
            chargeKeys: store
        )
        try await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .ready, "the fixture itself is broken if this fails")
        return (ttp, provider)
    }

    private static func failure(_ work: () async throws -> some Any) async -> TapToPayError? {
        do {
            _ = try await work()
            XCTFail("expected the charge to fail")
        } catch let failure as TapToPayError {
            return failure
        } catch {
            XCTFail("expected a TapToPayError, got \(error)")
        }
        return nil
    }

    final class Wire: @unchecked Sendable {
        private let lock = NSLock()
        private var sentKeys: [String] = []
        private var initiate = 200

        var keys: [String] {
            lock.withLock { sentKeys }
        }

        var initiateStatus: Int {
            get { lock.withLock { initiate } }
            set { lock.withLock { initiate = newValue } }
        }

        func record(_ key: String?) {
            lock.withLock { sentKeys.append(key ?? "<none>") }
        }

        func reset() {
            lock.withLock {
                sentKeys = []
                initiate = 200
            }
        }
    }

    private static let stubHandler: StubURLProtocol.Handler = { request in
        let path = request.url?.path ?? ""
        var status = 200
        let body: [String: Any]
        if path.contains("/MoneyIn/initiate") {
            wire.record(request.value(forHTTPHeaderField: "idempotencyKey"))
            status = wire.initiateStatus
            body = status == 200
                ? ["code": "A01", "data": ["paymentTransId": "TXN-OVERLAP"]]
                : ["isSuccess": false, "responseText": "Refused"]
        } else if path.contains("/MoneyIn/update/") {
            body = ["code": "A01", "data": ["paymentTransId": "TXN-OVERLAP"]]
        } else {
            body = [
                "responseCode": 1,
                "isSuccess": true,
                "responseData": [
                    "credentials": ["secretKey": "s", "apiKey": "a", "merchantId": "m", "terminalId": "t"]
                ],
                "paymentToken": "payment_tok"
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!,
            data
        )
    }
}
