import XCTest
import PayabliSDKCore
import PayabliSDKTestUtils

final class TelemetryClientTests: XCTestCase {

    private func makeClient(
        enabled: Bool = true,
        batchSize: Int = 20
    ) async -> (TelemetryClient, InMemoryTelemetryTransport) {
        let transport = InMemoryTelemetryTransport()
        let client = TelemetryClient(
            configuration: .init(
                flushInterval: 30,
                batchSize: batchSize,
                enabled: enabled,
                entry: "test_entry",
                environment: "sandbox"
            ),
            transport: transport
        )
        return (client, transport)
    }

    func testEnqueuesAndFlushes() async {
        let (client, transport) = await makeClient(batchSize: 2)
        await client.emit("tokenization.started", properties: ["method": "card"])
        await client.emit("tokenization.succeeded", properties: ["method": "card", "durationMs": "1234"])

        let batches = await transport.batches
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.count, 2)
        XCTAssertEqual(batches.first?.first?.event, "tokenization.started")
    }

    func testDoesNotFlushBelowBatchSize() async {
        let (client, transport) = await makeClient(batchSize: 5)
        await client.emit("e1")
        await client.emit("e2")

        let batches = await transport.batches
        XCTAssertTrue(batches.isEmpty)
        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 2)
    }

    func testOptOutSuppressesEmission() async {
        let (client, transport) = await makeClient(enabled: false, batchSize: 1)
        await client.emit("never.sent")
        await client.flush()

        let batches = await transport.batches
        XCTAssertTrue(batches.isEmpty)
    }

    func testManualFlushSendsPartialBuffer() async {
        let (client, transport) = await makeClient(batchSize: 100)
        await client.emit("a")
        await client.emit("b")
        await client.emit("c")
        await client.flush()

        let batches = await transport.batches
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.count, 3)
    }

    func testDeviceIdIsHashedNotRaw() async {
        let (client, transport) = await makeClient(batchSize: 1)
        await client.setDeviceId("abc-device-123")
        await client.emit("event", properties: [:])

        let batches = await transport.batches
        let event = batches.first?.first
        XCTAssertNotNil(event?.deviceIdHash)
        XCTAssertNotEqual(event?.deviceIdHash, "abc-device-123")
        XCTAssertEqual(event?.deviceIdHash?.count, 64, "SHA-256 hex digest is 64 chars")
    }

    func testEnvelopeIncludesVersion() async {
        let (client, transport) = await makeClient(batchSize: 1)
        await client.emit("x")
        let batches = await transport.batches
        let event = batches.first?.first
        XCTAssertEqual(event?.schemaVersion, 1)
        XCTAssertEqual(event?.sdkVersion, "1.0.0")
    }
}
