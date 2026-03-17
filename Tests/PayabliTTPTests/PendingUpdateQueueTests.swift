import XCTest
@testable import PayabliTTP

final class PendingUpdateQueueTests: XCTestCase {

    private var queue: PendingUpdateQueue!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.pending.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        queue = PendingUpdateQueue(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testStartsEmpty() {
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.all().count, 0)
    }

    func testEnqueueAndRetrieve() {
        queue.enqueue(paymentTransId: "txn-1", responseDict: ["status": "CAPTURED"])

        XCTAssertFalse(queue.isEmpty)

        let items = queue.all()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.paymentTransId, "txn-1")
    }

    func testEnqueueMultiple() {
        queue.enqueue(paymentTransId: "txn-1", responseDict: ["a": 1])
        queue.enqueue(paymentTransId: "txn-2", responseDict: ["b": 2])

        XCTAssertEqual(queue.all().count, 2)
    }

    func testRemove() {
        queue.enqueue(paymentTransId: "txn-1", responseDict: ["a": 1])
        queue.enqueue(paymentTransId: "txn-2", responseDict: ["b": 2])

        queue.remove(paymentTransId: "txn-1")

        let items = queue.all()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.paymentTransId, "txn-2")
    }

    func testPersistsAcrossInstances() {
        queue.enqueue(paymentTransId: "txn-persist", responseDict: ["x": "y"])

        let newQueue = PendingUpdateQueue(defaults: defaults)
        XCTAssertFalse(newQueue.isEmpty)
        XCTAssertEqual(newQueue.all().first?.paymentTransId, "txn-persist")
    }

    func testResponseDictRoundtrip() {
        let original: [String: Any] = ["transactionState": "CAPTURED", "amount": 9.99]
        queue.enqueue(paymentTransId: "txn-rt", responseDict: original)

        let retrieved = queue.all().first
        XCTAssertNotNil(retrieved?.responseDict)
        XCTAssertEqual(retrieved?.responseDict?["transactionState"] as? String, "CAPTURED")
    }
}
