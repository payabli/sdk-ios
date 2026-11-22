@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// `closeCapturedCharge` for a payment this process does not hold: what it sends, what it reports, and how it
/// shares an entry point with a charge.
@available(iOS 16.7, *)
@MainActor
final class CloseCapturedChargeTests: XCTestCase {
    private static let wire = CloseWire()
    private static let notHeld = "TXN-NOT-HELD"
    private static let opened = "TXN-OPENED"
    private static let sale = PayabliTTPPaymentDetails(amount: 1, currency: .usd)
    /// One store for every terminal in a case, as the process has one.
    private let keys = ChargeKeyStore()

    override func setUp() {
        super.setUp()
        Self.wire.reset()
        StubURLProtocol.handler = Self.wire.handle
    }

    override func tearDown() {
        Self.wire.release()
        StubURLProtocol.handler = nil
        Self.wire.reset()
        super.tearDown()
    }

    // MARK: - What the close sends

    /// Nothing is held, as after a restart, and the identifier is all the close needs.
    func testAPaymentThisProcessDoesNotHoldIsClosedByItsIdentifierWithAnEmptyObject() async throws {
        let terminal = try makeTerminal(entryPoint: "an-entry-point-after-a-restart")

        try await terminal.closeCapturedCharge(paymentTransId: Self.notHeld)

        let closes = Self.wire.closes(of: Self.notHeld)
        XCTAssertEqual(closes.count, 1)
        XCTAssertEqual(closes.first?.method, "PATCH")
        XCTAssertEqual(closes.first?.body, Data("{}".utf8))
        XCTAssertEqual(closes.first?.contentType, "application/json")
    }

    /// A failed close may have landed with its answer lost, so the money is unknown, never not charged.
    func testAnUnheldCloseThatFailsIsPaymentNotClosedWithItsCaptureUnknown() async throws {
        Self.wire.script(updates: [500])
        let terminal = try makeTerminal()

        let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.notHeld) }

        XCTAssertEqual(failure?.type, .paymentNotClosed)
        XCTAssertEqual(failure?.paymentTransId, Self.notHeld)
        XCTAssertEqual(failure?.capture, .unknown)
        XCTAssertEqual(failure?.httpStatus, 500)
        XCTAssertEqual(Self.wire.closes(of: Self.notHeld).count, 3, "a server error is retried as the charge's close is")
    }

    func testACloseRunsUnderTheTerminalsRetryPolicy() async throws {
        Self.wire.script(updates: [500])
        let terminal = try makeTerminal(retryPolicy: RetryPolicy(
            maxAttempts: 1,
            baseDelay: 0,
            maxDelay: 0,
            multiplier: 1,
            maxJitter: 0,
            jitter: .none
        ))

        let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.notHeld) }

        XCTAssertEqual(failure?.type, .paymentNotClosed)
        XCTAssertEqual(Self.wire.closes(of: Self.notHeld).count, 1, "the close ran under another policy")
    }

    func testACloseTheCallerMayNotSendIsPermissionDeniedSentOnceWithNoTokenRenewed() async throws {
        Self.wire.script(updates: [400], refusal: "E9001")
        let tokens = TokenRequests()
        let terminal = try makeTerminal(tokens: tokens)

        let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.notHeld) }

        XCTAssertEqual(failure?.type, .permissionDenied)
        XCTAssertEqual(failure?.rawCode, "E9001")
        XCTAssertEqual(failure?.httpStatus, 400)
        XCTAssertEqual(failure?.paymentTransId, Self.notHeld)
        XCTAssertEqual(failure?.capture, .unknown)
        XCTAssertEqual(Self.wire.closes(of: Self.notHeld).count, 1, "the refusal was sent again")
        XCTAssertEqual(tokens.value, 1, "a token was renewed after the refusal")
    }

    /// Any other 400 stays a close that was not confirmed.
    func testAnotherRefusalOfTheCloseIsPaymentNotClosed() async throws {
        Self.wire.script(updates: [400], refusal: "E7000")
        let terminal = try makeTerminal()

        let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.notHeld) }

        XCTAssertEqual(failure?.type, .paymentNotClosed)
        XCTAssertEqual(failure?.rawCode, "E7000")
    }

    /// A dot segment would name another route once sent.
    func testAnIdentifierThatCannotNameOneTransactionIsRefusedUnsent() async throws {
        let terminal = try makeTerminal()

        for unaddressable in ["", " ", ".", "..", "\u{1C}", " .\u{1F}"] {
            let failure = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: unaddressable) }

            XCTAssertEqual(failure?.type, .paymentNotClosed, "\"\(unaddressable)\"")
            XCTAssertEqual(failure?.paymentTransId, unaddressable, "\"\(unaddressable)\"")
            XCTAssertEqual(failure?.capture, .unknown, "\"\(unaddressable)\"")
        }
        XCTAssertTrue(Self.wire.updates.isEmpty, "a close was sent: \(Self.wire.updates.map(\.path))")
    }

    /// U+0085 and U+200B are not blank, so an identifier of either names a transaction.
    func testAnIdentifierOfCharactersThatAreNotBlankIsSent() async throws {
        let terminal = try makeTerminal()

        for addressable in ["\u{85}", "\u{200B}"] {
            try await terminal.closeCapturedCharge(paymentTransId: addressable)
        }
        XCTAssertEqual(Self.wire.updates.count, 2, "\(Self.wire.updates.map(\.path))")
    }

    /// The charge's own close carried the read's failure, and the second close carries no outcome.
    func testAPaymentWhoseChargeFailedBeforeTheReaderAnsweredClosesAgain() async throws {
        let (terminal, provider) = try await makeReadyTerminal()
        provider.readingResult = .failure(PayabliTTPError.nfcFailed(reason: "read failed"))
        let failure = await Self.failure { _ = try await terminal.charge(paymentDetails: Self.sale) }
        let paymentTransId = try XCTUnwrap(failure?.paymentTransId)

        try await terminal.closeCapturedCharge(paymentTransId: paymentTransId)

        let closes = Self.wire.closes(of: paymentTransId)
        XCTAssertEqual(closes.count, 2)
        XCTAssertEqual(closes.last?.body, Data("{}".utf8))
    }

    // MARK: - The session

    /// A terminal that was never initialized closes too.
    func testAnUninitializedTerminalClosesAndItsStateDoesNotMove() async throws {
        let terminal = try makeTerminal()
        var states: [PayabliTTPSessionState] = []
        let watching = terminal.$sessionState.dropFirst().sink { states.append($0) }

        try await terminal.closeCapturedCharge(paymentTransId: Self.notHeld)

        watching.cancel()
        XCTAssertEqual(terminal.sessionState, .idle)
        XCTAssertEqual(states, [])
        XCTAssertEqual(Self.wire.closes(of: Self.notHeld).count, 1)
    }

    func testAReadyTerminalStaysReadyThroughTheClose() async throws {
        let (terminal, _) = try await makeReadyTerminal()
        var states: [PayabliTTPSessionState] = []
        let watching = terminal.$sessionState.dropFirst().sink { states.append($0) }

        try await terminal.closeCapturedCharge(paymentTransId: Self.notHeld)

        watching.cancel()
        XCTAssertEqual(terminal.sessionState, .ready)
        XCTAssertEqual(states, [])
    }

    // MARK: - Cancellation

    /// The update answers 500 once the caller has cancelled, then 200, so the second update is sent by a close its
    /// caller cannot stop.
    func testACancelledCallerGetsItsCancellationAndTheCloseFinishes() async throws {
        Self.wire.script(updates: [500, 200])
        Self.wire.holdUpdates()
        let terminal = try makeTerminal()

        let closing = Task { try await terminal.closeCapturedCharge(paymentTransId: Self.notHeld) }
        await Self.wire.waitUntilAnUpdateArrives()
        closing.cancel()
        Self.wire.release()

        do {
            try await closing.value
            XCTFail("a cancelled caller was told the close landed")
        } catch is CancellationError {}
        XCTAssertEqual(Self.wire.closes(of: Self.notHeld).count, 2, "the close stopped with its caller")
    }

    /// A session is replaced only once its credential is finished, so the retired terminal's close stops at that
    /// credential rather than at a liveness check, and the replacement's credentials are never borrowed.
    func testARetiredTerminalsCloseIsRefusedUnsentAndAsksNeitherProvider() async throws {
        PayabliSession.resetForTesting()
        defer { PayabliSession.resetForTesting() }
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!, Data())
        }
        let firstTokens = TokenRequests()
        let replacementTokens = TokenRequests()
        let first = try PayabliSession.install(
            config: PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: {
                await firstTokens.record()
                return UUID().uuidString
            }),
            urlSession: StubURLProtocol.makeSession(),
            telemetryTransport: InMemoryTelemetryTransport()
        )
        let retired = PayabliTTP(
            session: first,
            provider: MockTapToPayProvider(),
            attestation: MockDeviceAttestationService(),
            chargeKeys: keys,
            heldPayments: HeldPayments()
        )
        _ = try? await first.transport.perform(PayabliRequest(method: .get, path: "/api/v2/ping"))
        _ = try PayabliSession.install(
            config: PayabliConfig(entryPoint: "e", environment: .production, tokenProvider: {
                await replacementTokens.record()
                return "replacement"
            }),
            urlSession: StubURLProtocol.makeSession(),
            telemetryTransport: InMemoryTelemetryTransport()
        )
        XCTAssertFalse(retired.isLive())
        let firstAsks = firstTokens.value
        let stateBefore = retired.sessionState
        StubURLProtocol.handler = Self.wire.handle

        let error = await Self.failure { try await retired.closeCapturedCharge(paymentTransId: Self.notHeld) }

        XCTAssertEqual(error?.type, .paymentNotClosed)
        XCTAssertEqual(error?.capture, .unknown)
        XCTAssertEqual(error?.paymentTransId, Self.notHeld)
        XCTAssertTrue(Self.wire.updates.isEmpty, "a finished credential sent the close")
        XCTAssertEqual(firstTokens.value, firstAsks, "the finished credential asked its provider again")
        XCTAssertEqual(replacementTokens.value, 0, "the replacement's provider was asked")
        XCTAssertEqual(retired.sessionState, stateBefore)
    }

    // MARK: - Sharing the entry point with a charge

    /// The charge's own close goes first, and no close is sent while its card is read.
    func testACloseDuringAChargeOnItsEntryPointWaitsForItThenSends() async throws {
        let (charging, provider) = try await makeReadyTerminal()
        let closer = try makeTerminal()
        let during = Overlap()
        provider.whileReading = {
            during.closing = Task { try await closer.closeCapturedCharge(paymentTransId: Self.notHeld) }
            during.sentDuringRead = await Self.wire.anUpdateArrives(for: Self.notHeld)
        }

        _ = try await charging.charge(paymentDetails: Self.sale)
        try await XCTUnwrap(during.closing).value

        XCTAssertFalse(during.sentDuringRead, "the close was sent while the card was read")
        XCTAssertEqual(Self.wire.updates.map(\.path), [CloseWire.path(Self.opened), CloseWire.path(Self.notHeld)])
    }

    func testACloseDuringAChargeOnAnotherEntryPointDoesNotWait() async throws {
        let (charging, provider) = try await makeReadyTerminal()
        let closer = try makeTerminal(entryPoint: "other")
        let during = Overlap()
        provider.whileReading = {
            during.closing = Task { try await closer.closeCapturedCharge(paymentTransId: Self.notHeld) }
            during.sentDuringRead = await Self.wire.anUpdateArrives(for: Self.notHeld)
        }

        _ = try await charging.charge(paymentDetails: Self.sale)
        try await XCTUnwrap(during.closing).value

        XCTAssertTrue(during.sentDuringRead, "a close waited for a charge on another entry point")
    }

    /// The wait is bounded at a second, so a close that keeps waiting for the charge fails rather than hangs.
    func testACloseCancelledWhileItWaitsForTheChargeEndsAtOnceAndSendsNothing() async throws {
        let (charging, provider) = try await makeReadyTerminal()
        let closer = try makeTerminal()
        let during = Overlap()
        provider.whileReading = {
            let closing = Task { try await closer.closeCapturedCharge(paymentTransId: Self.notHeld) }
            await Task.yield()
            closing.cancel()
            Task { during.closeResult = await closing.result }
            for _ in 0 ..< 100 where during.closeResult == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
            during.heldAfterCancel = SessionSetupGate.shared.isClosing("e")
        }

        _ = try await charging.charge(paymentDetails: Self.sale)

        let result = try XCTUnwrap(during.closeResult, "the cancelled close waited for the charge to end")
        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError, "\($0)") }
        XCTAssertFalse(during.heldAfterCancel, "the cancelled close still held its entry point")
        let sent = await Self.wire.anUpdateArrives(for: Self.notHeld)
        XCTAssertFalse(sent, "the cancelled close was sent")
    }

    func testAChargeArrivingWhileACloseRunsOnItsEntryPointIsRefusedUnsent() async throws {
        let (charging, provider) = try await makeReadyTerminal()
        let closer = try makeTerminal()
        Self.wire.holdUpdates()

        let closing = Task { try await closer.closeCapturedCharge(paymentTransId: Self.notHeld) }
        await Self.wire.waitUntilAnUpdateArrives()
        let refusal = await Self.failure { _ = try await charging.charge(paymentDetails: Self.sale) }
        Self.wire.release()
        try await closing.value

        XCTAssertEqual(refusal?.type, .terminalNotReady)
        XCTAssertEqual(refusal?.capture, .notCharged)
        XCTAssertEqual(Self.wire.openings, 0, "the refused charge opened a payment")
        XCTAssertEqual(provider.startReadingCalls, 0)
        XCTAssertEqual(charging.sessionState, .ready)
    }

    /// The close is held at its token rather than on the wire, where a held request stalls every other one.
    func testAChargeOnAnotherEntryPointIsAdmittedWhileACloseRuns() async throws {
        let (charging, _) = try await makeReadyTerminal(entryPoint: "other")
        let tokens = TokenRequests(held: true)
        let closer = try makeTerminal(tokens: tokens)

        let closing = Task { try await closer.closeCapturedCharge(paymentTransId: Self.notHeld) }
        await tokens.waitUntilAsked()
        _ = try await charging.charge(paymentDetails: Self.sale)
        tokens.release()
        try await closing.value

        XCTAssertEqual(Self.wire.openings, 1)
        XCTAssertEqual(Self.wire.updates.map(\.path), [CloseWire.path(Self.opened), CloseWire.path(Self.notHeld)])
    }

    /// Each close is held at its own token, so the first can end while the second still runs.
    func testAChargeIsRefusedUntilTheLastOfTwoClosesOnItsEntryPointEnds() async throws {
        let (charging, provider) = try await makeReadyTerminal()
        let firstTokens = TokenRequests(held: true)
        let secondTokens = TokenRequests(held: true)
        let first = try makeTerminal(tokens: firstTokens)
        let second = try makeTerminal(tokens: secondTokens)

        let firstClosing = Task { try await first.closeCapturedCharge(paymentTransId: Self.notHeld) }
        let secondClosing = Task { try await second.closeCapturedCharge(paymentTransId: Self.notHeld) }
        await firstTokens.waitUntilAsked()
        await secondTokens.waitUntilAsked()
        firstTokens.release()
        try await firstClosing.value

        let refusal = await Self.failure { _ = try await charging.charge(paymentDetails: Self.sale) }
        XCTAssertEqual(refusal?.type, .terminalNotReady, "a charge was admitted while a close still ran")
        XCTAssertEqual(Self.wire.openings, 0, "the refused charge opened a payment")
        XCTAssertEqual(provider.startReadingCalls, 0)

        secondTokens.release()
        try await secondClosing.value
        _ = try await charging.charge(paymentDetails: Self.sale)

        XCTAssertEqual(Self.wire.openings, 1, "the charge after the last close was not admitted")
    }

    /// The retry's key is being sent by the running charge, whether or not a close waits behind it.
    func testARetryWhoseKeyIsBeingSentIsRefusedOpenWhileACloseWaitsBehindTheCharge() async throws {
        let (charging, provider) = try await makeReadyTerminal()
        let (retrying, retryingProvider) = try await makeReadyTerminal()
        let closer = try makeTerminal()
        let during = Overlap()
        provider.whileReading = {
            during.closing = Task { try await closer.closeCapturedCharge(paymentTransId: Self.notHeld) }
            await Task.yield()
            during.refusal = await Self.failure {
                _ = try await retrying.charge(paymentDetails: Self.sale, attempt: .retry)
            }
        }

        _ = try await charging.charge(paymentDetails: Self.sale)
        try await XCTUnwrap(during.closing).value

        XCTAssertEqual(during.refusal?.type, .paymentReferenceOpen)
        XCTAssertEqual(Self.wire.openings, 1, "the refused retry sent its key")
        XCTAssertEqual(retryingProvider.startReadingCalls, 0)
    }

    /// A close that ends releases its entry point, so the charge after it is admitted.
    func testAChargeAfterAFailedCloseIsAdmitted() async throws {
        Self.wire.script(updates: [500])
        let (terminal, _) = try await makeReadyTerminal()

        _ = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.notHeld) }
        Self.wire.script(updates: [200])
        _ = try await terminal.charge(paymentDetails: Self.sale)

        XCTAssertEqual(Self.wire.openings, 1)
    }

    // MARK: - Objective-C

    func testTheObjectiveCCloseCompletesOnTheMainThreadWithNilWhenTheCloseLands() async throws {
        let terminal = try makeTerminal()
        let completed = expectation(description: "completion")
        var received: NSError? = NSError(domain: "unset", code: 0)
        var onMain = false

        terminal.closeCapturedCharge(Self.notHeld) { error in
            received = error
            onMain = Thread.isMainThread
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)

        XCTAssertNil(received)
        XCTAssertTrue(onMain)
    }

    func testTheObjectiveCCloseCompletesOnTheMainThreadWithTheCatalogNumberAndThePayment() async throws {
        Self.wire.script(updates: [500])
        let terminal = try makeTerminal()
        let completed = expectation(description: "completion")
        var received: NSError?
        var onMain = false

        terminal.closeCapturedCharge(Self.notHeld) { error in
            received = error
            onMain = Thread.isMainThread
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)

        let error = try XCTUnwrap(received)
        XCTAssertTrue(onMain)
        XCTAssertEqual(error.domain, TapToPayError.errorDomain)
        XCTAssertEqual(error.code, 3022)
        XCTAssertEqual(error.userInfo["paymentTransId"] as? String, Self.notHeld)
        XCTAssertEqual(error.userInfo["capture"] as? Int, PayabliTTPCapture.unknown.rawValue)
    }

    // MARK: - Fixtures

    @MainActor
    private final class Overlap {
        var closing: Task<Void, Error>?
        var sentDuringRead = false
        var refusal: TapToPayError?
        var closeResult: Result<Void, Error>?
        var heldAfterCancel = true
    }

    /// Counts the token provider's calls, and can keep each call waiting until ``release()``.
    final class TokenRequests: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var held: Bool
        private var waiting: [CheckedContinuation<Void, Never>] = []

        init(held: Bool = false) {
            self.held = held
        }

        var value: Int {
            lock.withLock { count }
        }

        func record() async {
            await withCheckedContinuation { continuation in
                let resumeNow = lock.withLock {
                    count += 1
                    if held {
                        waiting.append(continuation)
                    }
                    return !held
                }
                if resumeNow {
                    continuation.resume()
                }
            }
        }

        func release() {
            let resumed = lock.withLock {
                held = false
                defer { waiting = [] }
                return waiting
            }
            resumed.forEach { $0.resume() }
        }

        func waitUntilAsked(file: StaticString = #filePath, line: UInt = #line) async {
            for _ in 0 ..< 300 {
                if value > 0 {
                    return
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTFail("the token was never asked for", file: file, line: line)
        }
    }

    private func makeTerminal(
        entryPoint: String = "e",
        tokens: TokenRequests = TokenRequests(),
        retryPolicy: RetryPolicy = noWait
    ) throws -> PayabliTTP {
        let config = try PayabliConfig(
            entryPoint: entryPoint,
            environment: .sandbox,
            tokenProvider: {
                await tokens.record()
                return "token"
            }
        )
        return PayabliTTP(
            config: config,
            provider: MockTapToPayProvider(),
            attestation: MockDeviceAttestationService(),
            retryPolicy: retryPolicy,
            session: StubURLProtocol.makeSession(),
            chargeKeys: keys
        )
    }

    private func makeReadyTerminal(entryPoint: String = "e") async throws -> (PayabliTTP, MockTapToPayProvider) {
        let provider = MockTapToPayProvider()
        provider.readingResult = .success(CardReadResult(provider: "mock", encryptedPayload: Data(), outcome: .approved))
        let config = try PayabliConfig(entryPoint: entryPoint, environment: .sandbox, tokenProvider: { "token" })
        let terminal = PayabliTTP(
            config: config,
            provider: provider,
            attestation: MockDeviceAttestationService(),
            retryPolicy: Self.noWait,
            session: StubURLProtocol.makeSession(),
            chargeKeys: keys
        )
        try await terminal.initialize()
        XCTAssertEqual(terminal.sessionState, .ready, "the fixture itself is broken if this fails")
        return (terminal, provider)
    }

    /// Three attempts with no wait between them.
    private static let noWait = RetryPolicy(
        maxAttempts: 3,
        baseDelay: 0,
        maxDelay: 0,
        multiplier: 1,
        maxJitter: 0,
        jitter: .none
    )

    private static func failure(_ body: @MainActor () async throws -> Void) async -> TapToPayError? {
        do {
            try await body()
            XCTFail("expected a failure")
        } catch let failure as TapToPayError {
            return failure
        } catch {
            XCTFail("expected a TapToPayError, got \(error)")
        }
        return nil
    }
}

/// The service a close and a charge reach: it opens `TXN-OPENED`, answers each update from a script, and can hold
/// updates until released.
final class CloseWire: @unchecked Sendable {
    struct Update {
        let path: String
        let method: String
        let body: Data
        let contentType: String?
    }

    private let lock = NSLock()
    private var statuses: [Int] = [200]
    private var refusal: String?
    private var detail: String?
    private var answered = 0
    private var recorded: [Update] = []
    private var opened = 0
    private var holding: DispatchSemaphore?

    static func path(_ paymentTransId: String) -> String {
        "/api/v2/MoneyIn/update/\(paymentTransId)"
    }

    func reset() {
        lock.withLock {
            statuses = [200]
            refusal = nil
            detail = nil
            answered = 0
            recorded = []
            opened = 0
            holding = nil
        }
    }

    /// - Parameters:
    ///   - updates: the status each update is answered with, the last repeating.
    ///   - refusal: the `code` a non-2xx answer carries.
    ///   - detail: the `detail` a non-2xx answer carries.
    func script(updates: [Int], refusal: String? = nil, detail: String? = nil) {
        lock.withLock {
            statuses = updates
            self.refusal = refusal
            self.detail = detail
            answered = 0
        }
    }

    /// Holds every update that arrives until ``release()``.
    func holdUpdates() {
        lock.withLock { holding = DispatchSemaphore(value: 0) }
    }

    /// Lets every held update answer, and stops holding.
    func release() {
        lock.withLock {
            for _ in 0 ..< 8 {
                holding?.signal()
            }
            holding = nil
        }
    }

    var updates: [Update] {
        lock.withLock { recorded }
    }

    var openings: Int {
        lock.withLock { opened }
    }

    func closes(of paymentTransId: String) -> [Update] {
        updates.filter { $0.path == Self.path(paymentTransId) }
    }

    func waitUntilAnUpdateArrives(file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0 ..< 300 {
            if !updates.isEmpty {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("no update arrived", file: file, line: line)
    }

    /// Whether a close of `paymentTransId` arrives within half a second.
    ///
    /// - Parameter paymentTransId: the payment whose close is waited for.
    /// - Returns: `true` once one has arrived, `false` when none did in time.
    func anUpdateArrives(for paymentTransId: String) async -> Bool {
        for _ in 0 ..< 50 {
            if !closes(of: paymentTransId).isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    func handle(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""
        var status = 200
        let body: [String: Any]
        if path.contains("/MoneyIn/initiate") {
            lock.withLock { opened += 1 }
            body = ["code": "A01", "data": ["paymentTransId": "TXN-OPENED"]]
        } else if path.contains("/MoneyIn/update/") {
            let held: DispatchSemaphore? = lock.withLock {
                recorded.append(Update(
                    path: path,
                    method: request.httpMethod ?? "",
                    body: request.httpBody ?? Data(),
                    contentType: request.value(forHTTPHeaderField: "Content-Type")
                ))
                status = statuses[min(answered, statuses.count - 1)]
                answered += 1
                return holding
            }
            _ = held?.wait(timeout: .now() + 5)
            let (refusal, detail) = lock.withLock { (self.refusal, self.detail) }
            var refused: [String: Any] = ["code": refusal ?? "E0000", "reason": "refused"]
            refused["detail"] = detail
            body = (200 ..< 300).contains(status) ? ["code": "A01"] : refused
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
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}
