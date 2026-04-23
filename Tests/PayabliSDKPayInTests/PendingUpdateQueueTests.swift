import XCTest
@testable import PayabliSDKPayIn

final class PendingUpdateQueueTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "com.payabli.tests.queue"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func queue() -> PendingUpdateQueue { PendingUpdateQueue(defaults: defaults) }

    private func makeUpdate(id: String, daysOld: TimeInterval = 0) -> PendingUpdate {
        PendingUpdate(
            paymentTransId: id,
            updateBody: Data("body_\(id)".utf8),
            createdAt: Date().addingTimeInterval(-daysOld * 24 * 3600)
        )
    }

    // MARK: - Enqueue / persist

    func testEnqueueAndLoadRoundTrip() {
        let q = queue()
        q.enqueue(makeUpdate(id: "a"))
        q.enqueue(makeUpdate(id: "b"))
        let loaded = q.load()
        XCTAssertEqual(loaded.map(\.paymentTransId), ["a", "b"])
    }

    func testRemoveByPaymentTransId() {
        let q = queue()
        q.enqueue(makeUpdate(id: "a"))
        q.enqueue(makeUpdate(id: "b"))
        q.remove(paymentTransId: "a")
        XCTAssertEqual(q.load().map(\.paymentTransId), ["b"])
    }

    // MARK: - Max size (FIFO eviction)

    func testEnforcesMaxEntries() {
        let q = queue()
        for i in 0..<PendingUpdateQueue.maxEntries {
            q.enqueue(makeUpdate(id: "tx_\(i)"))
        }
        XCTAssertEqual(q.load().count, PendingUpdateQueue.maxEntries)
        // Add one more — should evict the oldest.
        q.enqueue(makeUpdate(id: "tx_overflow"))
        let loaded = q.load()
        XCTAssertEqual(loaded.count, PendingUpdateQueue.maxEntries)
        XCTAssertEqual(loaded.last?.paymentTransId, "tx_overflow")
        XCTAssertEqual(loaded.first?.paymentTransId, "tx_1", "Oldest entry should be evicted")
    }

    // MARK: - TTL eviction

    func testTTLEvictsStaleEntries() {
        let q = queue()
        q.enqueue(makeUpdate(id: "fresh", daysOld: 1))
        q.enqueue(makeUpdate(id: "stale", daysOld: 10))
        let cleaned = q.evictExpired()
        XCTAssertEqual(cleaned.map(\.paymentTransId), ["fresh"])
        XCTAssertEqual(q.load().map(\.paymentTransId), ["fresh"])
    }

    // MARK: - Forward-compatible decoding (FR-11E.4)

    func testDropsCorruptEntriesKeepsValidOnes() throws {
        let q = queue()
        // Write an array with one valid entry and one malformed entry.
        let raw: [Any] = [
            [
                "paymentTransId": "good",
                "updateBody": Data("x".utf8).base64EncodedString(),
                "createdAt": "2026-04-21T00:00:00Z",
                "attemptCount": 0
            ],
            ["malformed": true]
        ]
        let data = try JSONSerialization.data(withJSONObject: raw)
        defaults.set(data, forKey: PendingUpdateQueue.storageKey)

        let loaded = q.load()
        XCTAssertEqual(loaded.map(\.paymentTransId), ["good"])
    }
}
