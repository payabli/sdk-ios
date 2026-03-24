import XCTest
@testable import PayabliTTP

final class PaymentOrchestratorTests: XCTestCase {

    private var http: MockNetworking!
    private var cardReader: MockCardReader!
    private var pendingQueue: PendingUpdateQueue!
    private var events: EventStream!
    private var sut: PaymentOrchestrator!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        http = MockNetworking()
        cardReader = MockCardReader()
        suiteName = "test.orchestrator.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        pendingQueue = PendingUpdateQueue(defaults: defaults)
        events = EventStream()

        let transactionService = TransactionService(http: http)
        transactionService.configure(requestToken: "mock-token")

        sut = PaymentOrchestrator(
            transactionService: transactionService,
            cardReader: cardReader,
            deviceId: "test-device-id",
            pendingQueue: pendingQueue,
            events: events,
            entry: "test-entry"
        )
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Happy path

    func testChargeSaleFullFlow() async throws {
        // Queue: initiate response, then void for update
        http.responses = [TestFixtures.makeTransactionResponse(paymentTransId: "txn-happy")]

        let result = try await sut.chargeSale(
            amount: 9.99,
            order: nil,
            customer: CustomerData(firstName: "Test"),
            invoice: nil,
            serviceFee: nil
        )

        XCTAssertEqual(result.transactionId, "txn-happy")
        XCTAssertEqual(result.syncStatus, .synced)
        XCTAssertTrue(cardReader.chargeCalled)
    }

    func testChargeSaleWithAllParameters() async throws {
        http.responses = [TestFixtures.makeTransactionResponse(paymentTransId: "txn-full")]

        let result = try await sut.chargeSale(
            amount: 25.50,
            order: OrderDetails(orderId: "ORD-123", description: "Test order"),
            customer: CustomerData(firstName: "Jane", lastName: "Doe"),
            invoice: InvoiceData(
                invoiceNumber: "INV-001",
                items: [LineItem(name: "Widget", amount: 25.00, quantity: 1)]
            ),
            serviceFee: 0.50
        )

        XCTAssertEqual(result.transactionId, "txn-full")
        XCTAssertEqual(result.syncStatus, .synced)
    }

    // MARK: - NFC failure

    func testChargeSaleNFCFailure() async {
        http.responses = [TestFixtures.makeTransactionResponse()]
        cardReader.shouldFailCharge = true

        do {
            _ = try await sut.chargeSale(
                amount: 5.00, order: nil, customer: nil, invoice: nil, serviceFee: nil
            )
            XCTFail("Should have thrown")
        } catch {
            guard case PayabliTTPError.fiservError = error else {
                XCTFail("Expected fiservError, got \(error)")
                return
            }
        }
    }

    // MARK: - Update failure → pending queue

    func testUpdateFailureQueuesPendingUpdate() async throws {
        http.responses = [TestFixtures.makeTransactionResponse(paymentTransId: "txn-pending")]
        // Initiate succeeds (execute), update fails on all 3 retry attempts (executeVoid).
        // RetryPolicy only retries on networkError/5xx, so we use a non-retryable error to
        // skip the actual sleeps and trigger the queue path immediately.
        let updateError = PayabliTTPError.backendError(statusCode: 503, message: "Service unavailable")
        http.executeVoidResponses = [updateError, updateError, updateError]

        let result = try await sut.chargeSale(
            amount: 5.00, order: nil, customer: nil, invoice: nil, serviceFee: nil
        )

        XCTAssertEqual(result.transactionId, "txn-pending")
        XCTAssertEqual(result.syncStatus, .pendingSyncWithBackend)
        XCTAssertFalse(pendingQueue.isEmpty, "Failed update should be queued")
        XCTAssertEqual(pendingQueue.all().first?.paymentTransId, "txn-pending")
        XCTAssertFalse(pendingQueue.all().first?.isErrorUpdate ?? true, "Should be a success update")
    }

    func testNFCFailureQueuesErrorUpdateWhenPATCHFails() async throws {
        http.responses = [TestFixtures.makeTransactionResponse(paymentTransId: "txn-nfc-fail")]
        cardReader.shouldFailCharge = true
        // Make the error-update PATCH also fail on all retry attempts.
        let updateError = PayabliTTPError.backendError(statusCode: 503, message: "Service unavailable")
        http.executeVoidResponses = [updateError, updateError, updateError]

        do {
            _ = try await sut.chargeSale(
                amount: 5.00, order: nil, customer: nil, invoice: nil, serviceFee: nil
            )
            XCTFail("Should have thrown fiservError")
        } catch PayabliTTPError.fiservError {
            // expected
        }

        XCTAssertFalse(pendingQueue.isEmpty, "Failed error-update should be queued")
        let queued = pendingQueue.all().first
        XCTAssertEqual(queued?.paymentTransId, "txn-nfc-fail")
        XCTAssertTrue(queued?.isErrorUpdate ?? false, "Should be an error update")
    }

    // MARK: - Retry pending updates

    func testRetryPendingUpdatesSuccess() async {
        pendingQueue.enqueue(paymentTransId: "txn-retry", responseDict: ["status": "CAPTURED"])

        XCTAssertFalse(pendingQueue.isEmpty)

        await sut.retryPendingUpdates()

        XCTAssertTrue(pendingQueue.isEmpty, "Successful retry should remove from queue")
    }

    func testRetryPendingUpdatesFailureKeepsInQueue() async {
        pendingQueue.enqueue(paymentTransId: "txn-stuck", responseDict: ["status": "CAPTURED"])

        http.shouldFail = PayabliTTPError.networkError("offline")

        // Re-create with failing http
        let transactionService = TransactionService(http: http)
        transactionService.configure(requestToken: "mock-token")

        sut = PaymentOrchestrator(
            transactionService: transactionService,
            cardReader: cardReader,
            deviceId: "test-device-id",
            pendingQueue: pendingQueue,
            events: events,
            entry: "test-entry"
        )

        await sut.retryPendingUpdates()

        XCTAssertFalse(pendingQueue.isEmpty, "Failed retry should keep item in queue")
    }

    // MARK: - Initiate failure

    func testChargeSaleInitiateFailure() async {
        http.shouldFail = PayabliTTPError.backendError(statusCode: 500, message: "Server error")

        do {
            _ = try await sut.chargeSale(
                amount: 10.00, order: nil, customer: nil, invoice: nil, serviceFee: nil
            )
            XCTFail("Should have thrown")
        } catch {
            XCTAssertFalse(cardReader.chargeCalled, "Should not attempt NFC if initiate fails")
        }
    }
}
