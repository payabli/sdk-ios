import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

@MainActor
final class PayabliPayInReadTransactionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    func testAReadSendsNoKeyAndReturnsTheTransaction() async throws {
        let transport = RecordingIdempotencyTransport(body: Self.record)
        let flow = PayInFixture.makeFlow(transport: transport, key: "unused")

        let transaction = try await flow.readTransaction("101-abc")

        XCTAssertEqual(transaction.paymentTransId, "101-abc")
        XCTAssertEqual(transaction.status, .voided)
        XCTAssertEqual(transport.count, 1)
        XCTAssertEqual(transport.sentKeys, [])
    }

    func testAReadLeavesThePublishedResultAlone() async throws {
        let transport = RecordingIdempotencyTransport(bodies: [PayInFixture.approved, Self.record])
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-1")

        let captured = try await flow.capture(PayInFixture.request())
        _ = try await flow.readTransaction("101-abc")

        XCTAssertEqual(flow.lastResult, captured)
    }

    func testAReadRunsWhileASubmissionIsInFlight() async throws {
        let transport = HeldSubmissionTransport(read: Self.record)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-2")

        let submission = Task { try await flow.capture(PayInFixture.request()) }
        await transport.waitForTheSubmission()
        XCTAssertTrue(flow.isSubmitting)

        let transaction = try await flow.readTransaction("101-abc")

        XCTAssertEqual(transaction.paymentTransId, "101-abc")
        await transport.releaseTheSubmission()
        _ = try? await submission.value
    }

    private static let record = Data("""
    {"PaymentTransId": "101-abc", "TransStatus": 5, "Method": "card", "TotalAmount": 1.10}
    """.utf8)
}

/// Holds a POST until released and answers a GET at once, so a read can run beside a submission.
private actor HeldSubmissionTransport: PayabliTransport {
    private let read: Data
    private var submissionArrived: CheckedContinuation<Void, Never>?
    private var submissionHeld: CheckedContinuation<Void, Never>?
    private var hasSubmission = false

    init(read: Data) {
        self.read = read
    }

    func waitForTheSubmission() async {
        guard !hasSubmission else { return }
        await withCheckedContinuation { submissionArrived = $0 }
    }

    func releaseTheSubmission() {
        submissionHeld?.resume()
        submissionHeld = nil
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        guard request.method == .post else {
            return PayabliResponse(statusCode: 200, headers: [:], body: read)
        }
        hasSubmission = true
        submissionArrived?.resume()
        submissionArrived = nil
        await withCheckedContinuation { submissionHeld = $0 }
        return PayabliResponse(statusCode: 201, headers: [:], body: PayInFixture.approved)
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        let response = try await perform(request)
        return try JSONDecoder().decode(PayabliV2Envelope<T>.self, from: response.body)
    }
}

final class PayabliPayInTransactionObjCTests: XCTestCase {
    func testTheObjectiveCTransactionCarriesTheStatusByName() {
        let transaction = PayabliPayInTransactionObjC(
            PayabliPayInTransaction(paymentTransId: "trans-1", transStatus: 5, totalAmount: 1.10)
        )

        XCTAssertEqual(transaction.paymentTransId, "trans-1")
        XCTAssertEqual(transaction.transStatus, 5)
        XCTAssertEqual(transaction.status, "voided")
        XCTAssertEqual(transaction.totalAmount, 1.10)
    }

    func testAnUnnamedStatusIsOtherAndKeepsItsNumber() {
        let transaction = PayabliPayInTransactionObjC(PayabliPayInTransaction(transStatus: 99))

        XCTAssertEqual(transaction.status, "other")
        XCTAssertEqual(transaction.transStatus, 99)
    }

    func testNoStatusNumberIsNoStatus() {
        XCTAssertNil(PayabliPayInTransactionObjC(PayabliPayInTransaction()).status)
    }
}
