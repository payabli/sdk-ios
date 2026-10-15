@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// What the telemetry route reads: the `{ entry, events }` envelope, a string schema version, UTC
/// milliseconds, and the device facts beneath every event.
final class TelemetryWireContractTests: XCTestCase {
    private let facts = TelemetryDeviceFacts(
        deviceType: "Softpos",
        deviceOs: "Ios",
        osVersion: "18.6",
        modelName: "iPhone12,3",
        packageName: "com.example.merchant"
    )

    func testTheBatchIsTheShapeTheServiceAccepts() async throws {
        let stub = RecordingStub(status: 202, body: Data("{}".utf8))
        stub.install()
        defer { stub.uninstall() }

        await makeTransport(facts: facts).send([
            event(
                deviceIdHash: "9f2c4b7e1a05d38c6e4b90f7c2a1d5e3",
                properties: ["outcome": "approved"],
                timestamp: Date(timeIntervalSince1970: 1_755_000_000)
            )
        ])

        let expected = """
        {"entry":"an-entry-point","events":[{"schemaVersion":"1","sdkVersion":"0.1.0",\
        "timestamp":"2025-08-12T12:00:00.000Z","sessionId":"0f8d2a1c-4b6e-4a2f-9c3d-5e7f8a9b0c1d",\
        "entry":"an-entry-point","environment":"sandbox","event":"payin.capture.completed",\
        "properties":{"outcome":"approved"},"deviceIdHash":"9f2c4b7e1a05d38c6e4b90f7c2a1d5e3",\
        "deviceType":"Softpos","deviceOs":"Ios","osVersion":"18.6","modelName":"iPhone12,3",\
        "packageName":"com.example.merchant"}]}
        """
        XCTAssertEqual(stub.count, 1)
        XCTAssertEqual(try json(stub.requests.first?.httpBody), try json(Data(expected.utf8)))
    }

    func testATimestampKeepsItsMillisecondsInUTC() async throws {
        let stub = RecordingStub(status: 202)
        stub.install()
        defer { stub.uninstall() }

        await makeTransport(facts: facts).send([
            event(timestamp: Date(timeIntervalSince1970: 1_755_000_000.25))
        ])

        let sent = try XCTUnwrap(try firstEvent(stub.requests.first?.httpBody))
        XCTAssertEqual(sent["timestamp"] as? String, "2025-08-12T12:00:00.250Z")
    }

    func testABlankDeviceFactIsLeftOutAndNoneIsReachableAsAProperty() async throws {
        let stub = RecordingStub(status: 202)
        stub.install()
        defer { stub.uninstall() }
        let partial = TelemetryDeviceFacts(
            deviceType: nil,
            deviceOs: "Ios",
            osVersion: "",
            modelName: "iPhone12,3",
            packageName: nil
        )

        await makeTransport(facts: partial).send([event(properties: ["outcome": "failed"])])

        let sent = try XCTUnwrap(try firstEvent(stub.requests.first?.httpBody))
        XCTAssertNil(sent["deviceType"])
        XCTAssertNil(sent["osVersion"])
        XCTAssertNil(sent["packageName"])
        XCTAssertNil(sent["deviceIdHash"])
        XCTAssertEqual(sent["deviceOs"] as? String, "Ios")
        XCTAssertEqual(sent["properties"] as? [String: String], ["outcome": "failed"])
    }

    /// The service holds an undeclared member to printable ASCII, so a fact outside it is left out rather
    /// than transcoded, and the event still goes.
    func testADeviceFactOutsidePrintableASCIIIsLeftOut() {
        let facts = TelemetryDeviceFacts(
            deviceType: "Softpos",
            deviceOs: "Ios",
            osVersion: "18.6",
            modelName: "iPhone\u{00E9}",
            packageName: "com.example.merchant\n"
        )

        XCTAssertNil(facts.modelName)
        XCTAssertNil(facts.packageName)
        XCTAssertEqual(facts.osVersion, "18.6")
    }

    func testTheDeviceFactsNameThisPlatformInTheServicesWords() {
        let current = TelemetryDeviceFacts.current()

        XCTAssertEqual(current.deviceOs, "Ios")
        XCTAssertEqual(current.osVersion, DeviceModel.osVersion())
        XCTAssertEqual(current.modelName, DeviceModel.hardware())
        XCTAssertEqual(current.deviceType, CardPresentLinkage.isLinked ? "Softpos" : nil)
    }

    func testARefusedBatchIsObservedDiscardedAndTheNextOneStillGoes() async {
        let stub = RecordingStub(status: 401)
        stub.install()
        defer { stub.uninstall() }
        let sink = RecordingLogSink()
        let subject = makeTransport(facts: facts, sink: sink)

        await subject.send([event()])
        await subject.send([event()])

        XCTAssertEqual(stub.count, 2, "each batch is sent once and none is retried")
        let refusals = sink.records.filter { $0.message.contains("telemetry_batch_refused") }
        XCTAssertEqual(refusals.count, 2)
        XCTAssertTrue(refusals.allSatisfy { $0.message.contains("401") }, "\(refusals.map(\.message))")
    }

    func testAnAcceptedBatchIsNotReportedAsRefused() async {
        let stub = RecordingStub(status: 202, body: Data("{}".utf8))
        stub.install()
        defer { stub.uninstall() }
        let sink = RecordingLogSink()

        await makeTransport(facts: facts, sink: sink).send([event()])

        XCTAssertTrue(sink.records.filter { $0.message.contains("telemetry_batch_refused") }.isEmpty)
    }

    func testALinkageLookupAnswersByClassName() {
        XCTAssertTrue(CardPresentLinkage.resolves("NSObject"))
        XCTAssertFalse(CardPresentLinkage.resolves("PayabliNoSuchClassAnywhere"))
    }

    // MARK: - Helpers

    private func makeTransport(
        facts: TelemetryDeviceFacts,
        sink: RecordingLogSink = RecordingLogSink()
    ) -> TelemetryEndpointTransport {
        let service = PayabliService(
            environment: .sandbox,
            readToken: { "telemetry-token" },
            client: .none,
            session: StubURLProtocol.makeSession()
        )
        return TelemetryEndpointTransport(
            transport: service,
            deviceFacts: facts,
            logger: PayabliLogger(category: .telemetry, sink: sink)
        )
    }

    private func event(
        deviceIdHash: String? = nil,
        properties: [String: String] = [:],
        timestamp: Date = Date()
    ) -> TelemetryEvent {
        TelemetryEvent(
            sdkVersion: "0.1.0",
            sessionId: "0f8d2a1c-4b6e-4a2f-9c3d-5e7f8a9b0c1d",
            deviceIdHash: deviceIdHash,
            entry: "an-entry-point",
            environment: "sandbox",
            event: "payin.capture.completed",
            properties: properties,
            timestamp: timestamp
        )
    }

    private func json(_ data: Data?) throws -> NSDictionary {
        let body = try XCTUnwrap(data)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? NSDictionary)
    }

    private func firstEvent(_ data: Data?) throws -> [String: Any]? {
        let events = try json(data)["events"] as? [[String: Any]]
        return events?.first
    }
}
