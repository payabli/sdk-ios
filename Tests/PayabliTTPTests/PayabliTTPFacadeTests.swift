import XCTest
@testable import PayabliTTP

@MainActor
final class PayabliTTPFacadeTests: XCTestCase {

    private var http: MockNetworking!
    private var cardReader: MockCardReader!
    private var attester: MockDeviceAttester!
    private var storage: MockSecureStorage!
    private var sut: PayabliTTP!

    override func setUp() async throws {
        try await super.setUp()
        http = MockNetworking()
        cardReader = MockCardReader()
        attester = MockDeviceAttester(alreadyAttested: true)
        storage = MockSecureStorage()

        sut = PayabliTTP(
            configuration: PayabliTTPConfiguration(
                apiKey: "test-key",
                entry: "test-entry",
                deviceId: "test-device-id",
                appId: "TEAM123.com.test.app"
            ),
            storage: storage,
            http: http,
            attester: attester,
            cardReader: cardReader
        )
    }

    // MARK: - initialize()

    func testInitializeSetIsReadyAndSessionStateReady() async throws {
        http.responses = [TestFixtures.makeConfigResponse()]

        XCTAssertFalse(sut.isReady)
        XCTAssertEqual(sut.sessionState, .idle)

        try await sut.initialize()

        XCTAssertTrue(sut.isReady)
        XCTAssertEqual(sut.sessionState, .ready)
    }

    func testInitializeFailureSetsSessionStateError() async {
        // No mock response queued → network/decode error
        http.shouldFail = PayabliTTPError.networkError("simulated failure")

        do {
            try await sut.initialize()
            XCTFail("Expected initialize() to throw")
        } catch {
            XCTAssertFalse(sut.isReady)
            if case .error = sut.sessionState {
                // correct
            } else {
                XCTFail("Expected .error state, got \(sut.sessionState)")
            }
        }
    }

    func testInitializeAfterFailureSucceeds() async throws {
        // First attempt fails
        http.shouldFail = PayabliTTPError.networkError("offline")
        do { try await sut.initialize() } catch {}

        // Second attempt succeeds
        http.shouldFail = nil
        http.responses = [TestFixtures.makeConfigResponse()]
        try await sut.initialize()

        XCTAssertTrue(sut.isReady)
        XCTAssertEqual(sut.sessionState, .ready)
    }

    func testInitializeRunsPendingUpdatesOnSuccess() async throws {
        // Pre-populate pending queue via enqueue
        let defaults = UserDefaults(suiteName: "test.facade.\(UUID().uuidString)")!
        let pendingQueue = PendingUpdateQueue(defaults: defaults)
        pendingQueue.enqueue(paymentTransId: "stale-txn", responseDict: ["status": "CAPTURED"])

        sut = PayabliTTP(
            configuration: PayabliTTPConfiguration(
                apiKey: "test-key",
                entry: "test-entry",
                deviceId: "test-device-id",
                appId: "TEAM123.com.test.app"
            ),
            storage: storage,
            http: http,
            attester: attester,
            cardReader: cardReader,
            pendingQueue: pendingQueue
        )

        http.responses = [TestFixtures.makeConfigResponse()]

        try await sut.initialize()

        XCTAssertTrue(pendingQueue.isEmpty, "initialize() should retry and clear pending updates")
    }

    // MARK: - charge()

    func testChargeThrowsWhenSDKCannotInitialize() async {
        // SDK not initialized and backend is unreachable.
        // charge() calls reinitializeIfNeeded() → initialize() → fails → throws.
        http.shouldFail = PayabliTTPError.networkError("cannot reach server")

        do {
            _ = try await sut.charge(amount: 9.99, type: .sale)
            XCTFail("Expected charge to throw when SDK cannot initialize")
        } catch {
            XCTAssertFalse(sut.isReady, "SDK should not be ready after failed charge")
            if case .error = sut.sessionState {
                // correct — facade reflects the failed initialization
            } else {
                XCTFail("Expected .error session state, got \(sut.sessionState)")
            }
        }
    }

    func testChargeSucceedsAfterInitialize() async throws {
        http.responses = [TestFixtures.makeConfigResponse()]
        try await sut.initialize()

        http.responses = [TestFixtures.makeTransactionResponse(paymentTransId: "txn-facade")]

        let result = try await sut.charge(
            amount: 9.99,
            type: .sale,
            order: OrderDetails(orderId: "O-1", description: "Coffee"),
            customer: CustomerData(firstName: "Jane", lastName: "Doe")
        )

        XCTAssertEqual(result.transactionId, "txn-facade")
        XCTAssertEqual(result.syncStatus, .synced)
    }

    func testChargeCallsReinitializeIfNeeded() async throws {
        // Initialize then expire the session
        http.responses = [TestFixtures.makeConfigResponse()]
        try await sut.initialize()

        cardReader.isSessionActive = false
        http.responses = [
            TestFixtures.makeConfigResponse(),           // re-fetch config
            TestFixtures.makeTransactionResponse(paymentTransId: "txn-reinit")
        ]

        let result = try await sut.charge(amount: 5.00, type: .sale)

        XCTAssertEqual(result.transactionId, "txn-reinit")
        XCTAssertEqual(sut.sessionState, .ready)
    }

    // MARK: - reinitializeIfNeeded()

    func testReinitializeIfNeededFromIdleRunsFullInit() async throws {
        XCTAssertEqual(sut.sessionState, .idle)
        http.responses = [TestFixtures.makeConfigResponse()]

        try await sut.reinitializeIfNeeded()

        XCTAssertTrue(sut.isReady)
        XCTAssertEqual(sut.sessionState, .ready)
    }

    func testReinitializeIfNeededFromErrorRecovery() async throws {
        // Force .error state
        http.shouldFail = PayabliTTPError.networkError("offline")
        do { try await sut.initialize() } catch {}

        if case .error = sut.sessionState {
            // expected
        } else {
            XCTFail("Should be in .error state")
        }

        // Now recover
        http.shouldFail = nil
        http.responses = [TestFixtures.makeConfigResponse()]

        try await sut.reinitializeIfNeeded()

        XCTAssertTrue(sut.isReady)
        XCTAssertEqual(sut.sessionState, .ready)
    }

    func testReinitializeIfNeededWhileReadyAndActiveIsNoOp() async throws {
        http.responses = [TestFixtures.makeConfigResponse()]
        try await sut.initialize()

        cardReader.isSessionActive = true
        let callsBefore = http.executeCalled

        try await sut.reinitializeIfNeeded()

        XCTAssertEqual(http.executeCalled, callsBefore, "No HTTP calls expected when session is active")
        XCTAssertEqual(sut.sessionState, .ready)
    }

    // MARK: - @Published state propagation

    func testSessionStatePublishedOnInitialize() async throws {
        var states: [SessionState] = []
        let cancellable = sut.$sessionState.sink { states.append($0) }

        http.responses = [TestFixtures.makeConfigResponse()]
        try await sut.initialize()

        XCTAssertTrue(states.contains(.ready), "sessionState .ready should have been published")
        cancellable.cancel()
    }

    func testIsReadyPublishedOnInitialize() async throws {
        var readyValues: [Bool] = []
        let cancellable = sut.$isReady.sink { readyValues.append($0) }

        http.responses = [TestFixtures.makeConfigResponse()]
        try await sut.initialize()

        XCTAssertTrue(readyValues.contains(true), "isReady true should have been published")
        cancellable.cancel()
    }

    // MARK: - pendingUpdates

    func testPendingUpdatesReflectsQueue() async throws {
        http.responses = [TestFixtures.makeConfigResponse()]
        try await sut.initialize()

        XCTAssertTrue(sut.pendingUpdates.isEmpty)
    }
}
