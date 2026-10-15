@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// Reading a transaction back by its identifier.
final class PayInReadTransactionClientTests: XCTestCase {
    // MARK: - The request

    func testAReadIsAGetOnTheDetailsRouteWithNoBodyAndNoKey() async throws {
        let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.record())
        let client = PayInPaymentFlowClient(transport: transport)

        _ = try await client.details(transId: "101-abc")

        let request = try await onlyRequest(from: transport)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.path, "/api/MoneyIn/details/101-abc")
        XCTAssertNil(request.body)
        XCTAssertNil(request.headers["idempotencyKey"])
    }

    func testTheIdentifierIsTrimmedAndEscaped() async throws {
        let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.record(id: "a/b 1"))
        let client = PayInPaymentFlowClient(transport: transport)

        _ = try await client.details(transId: " a/b 1 ")

        let request = try await onlyRequest(from: transport)
        XCTAssertEqual(request.path, "/api/MoneyIn/details/a%2Fb%201")
    }

    func testABlankOrDotIdentifierIsRefusedBeforeAnythingIsSent() async {
        for transId in ["", "  ", ".", ".."] {
            let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.record())
            let client = PayInPaymentFlowClient(transport: transport)

            let error = await failure { _ = try await client.details(transId: transId) }

            XCTAssertEqual((error as? any PayabliError)?.type, .validation, "'\(transId)'")
            let sent = await transport.requests.count
            XCTAssertEqual(sent, 0, "'\(transId)'")
        }
    }

    func testTheRequestNamesA9001RefusalAsTheCallersAndNoOther401() async throws {
        let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.record())
        let client = PayInPaymentFlowClient(transport: transport)
        _ = try await client.details(transId: "101-abc")
        let request = try await onlyRequest(from: transport)

        XCTAssertTrue(request.isCallerRefusal(Self.response(401, Self.legacy(9001))))
        XCTAssertFalse(request.isCallerRefusal(Self.response(401, "")))
        XCTAssertFalse(request.isCallerRefusal(Self.response(401, Self.legacy(7001))))
        XCTAssertFalse(request.isCallerRefusal(Self.response(400, Self.legacy(9001))))
    }

    // MARK: - The answer

    func testARecordIsReadIntoTheTransactionsSharedFields() async throws {
        let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.record())
        let client = PayInPaymentFlowClient(transport: transport)

        let transaction = try await client.details(transId: "101-abc")

        XCTAssertEqual(transaction.paymentTransId, "101-abc")
        XCTAssertEqual(transaction.gatewayTransId, "gw-1")
        XCTAssertEqual(transaction.orderId, "order-1")
        XCTAssertEqual(transaction.method, "card")
        XCTAssertEqual(transaction.transStatus, 1)
        XCTAssertEqual(transaction.status, .captured)
        XCTAssertEqual(transaction.paypointId, 42)
        XCTAssertEqual(transaction.totalAmount, 1.10)
        XCTAssertEqual(transaction.netAmount, 1.00)
        XCTAssertEqual(transaction.feeAmount, 0.10)
        XCTAssertEqual(transaction.surchargeFee, 0)
    }

    func testNothingOutsideTheSharedFieldsIsFilled() async throws {
        let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.record())
        let client = PayInPaymentFlowClient(transport: transport)

        let transaction = try await client.details(transId: "101-abc")

        XCTAssertEqual(
            transaction,
            PayabliPayInTransaction(
                paymentTransId: "101-abc",
                gatewayTransId: "gw-1",
                orderId: "order-1",
                method: "card",
                transStatus: 1,
                paypointId: 42,
                totalAmount: 1.10,
                netAmount: 1.00,
                feeAmount: 0.10,
                surchargeFee: 0
            )
        )
    }

    func testARecordThatNamesNoTransactionOrAnotherIsUnreadable() async {
        for named in [nil, "", "  ", "202-xyz", "101-ABC"] as [String?] {
            let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.record(id: named))
            let client = PayInPaymentFlowClient(transport: transport)

            let error = await failure { _ = try await client.details(transId: "101-abc") }

            XCTAssertEqual((error as? any PayabliError)?.type, .decodingError, "\(String(describing: named))")
        }
    }

    func testAnUnknownIdentifierIsTransactionNotFound() async {
        let transport = MockPaymentCaptureTransport(statusCode: 400, responseBody: Self.legacy(7001))
        let client = PayInPaymentFlowClient(transport: transport)

        let error = await failure { _ = try await client.details(transId: "101-abc") }

        XCTAssertEqual((error as? any PayabliError)?.type, .transactionNotFound)
    }

    func testAnotherRefusalOnA400IsAValidationError() async {
        let transport = MockPaymentCaptureTransport(statusCode: 400, responseBody: Self.legacy(5000))
        let client = PayInPaymentFlowClient(transport: transport)

        let error = await failure { _ = try await client.details(transId: "101-abc") }

        XCTAssertEqual((error as? any PayabliError)?.type, .validation)
    }

    func testAPaypointTheCallerMayNotReadIsPermissionDenied() async {
        let transport = MockPaymentCaptureTransport(statusCode: 401, responseBody: Self.legacy(9001))
        let client = PayInPaymentFlowClient(transport: transport)

        let error = await failure { _ = try await client.details(transId: "101-abc") }

        XCTAssertEqual((error as? any PayabliError)?.type, .permissionDenied)
    }

    func testAServerFailureArrivesAsItselfAndNotAsAnUnknownOutcome() async {
        let transport = MockPaymentCaptureTransport(statusCode: 500, responseBody: "")
        let client = PayInPaymentFlowClient(transport: transport)

        let error = await failure { _ = try await client.details(transId: "101-abc") }

        XCTAssertEqual((error as? any PayabliError)?.type, .serverError)
        XCTAssertNil(error as? PayabliPayInError)
    }

    func testADiagnosticsEntryCarriesTheReadsStatusAndNoneOfItsBody() async throws {
        let entries = ReadDiagnosticEntries()
        let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.record())
        let client = PayInPaymentFlowClient(transport: transport, diagnostics: .enabled { entries.append($0) })

        _ = try await client.details(transId: "101-abc")

        let response = try XCTUnwrap(entries.all.first { $0.phase == .response })
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNil(response.body)
        let rendered = entries.all.map { "\($0.body ?? "") \($0.url)" }.joined(separator: "\n")
        for value in ["Pat Payer", "Payer Co", "203.0.113.7"] {
            XCTAssertFalse(rendered.contains(value), value)
        }
    }

    // MARK: - Fixtures

    /// A details record, PascalCase as the route answers, carrying fields that are never read.
    private static func record(id: String? = "101-abc") -> String {
        let named = id.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "PaymentTransId": \(named),
          "GatewayTransId": "gw-1",
          "OrderId": "order-1",
          "Method": "card",
          "TransStatus": 1,
          "PaypointId": 42,
          "TotalAmount": 1.10,
          "NetAmount": 1.00,
          "FeeAmount": 0.10,
          "SurchargeFee": 0,
          "SettlementStatus": 0,
          "Operation": "Sale",
          "IPAddress": "203.0.113.7",
          "Customer": { "FirstName": "Pat", "CompanyName": "Payer Co" },
          "PaymentData": { "HolderName": "Pat Payer" },
          "ResponseData": { "resultCode": "A0000", "authcode": "123456" }
        }
        """
    }

    private static func legacy(_ code: Int) -> String {
        """
        {"responseCode": \(code), "isSuccess": false, "responseText": "Error", "responseData": {}}
        """
    }

    private static func response(_ status: Int, _ body: String) -> PayabliResponse {
        PayabliResponse(statusCode: status, headers: [:], body: Data(body.utf8))
    }

    private func onlyRequest(
        from transport: MockPaymentCaptureTransport,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> PayabliRequest {
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1, file: file, line: line)
        return try XCTUnwrap(requests.first, file: file, line: line)
    }

    /// The error the block threw. A success fails the test, so the assertions after it are not skipped.
    private func failure(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: () async throws -> Void
    ) async -> any Error {
        do {
            try await block()
        } catch {
            return error
        }
        XCTFail("expected a failure", file: file, line: line)
        return CancellationError()
    }
}

private final class ReadDiagnosticEntries: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [PayabliPayInDiagnosticEntry] = []

    func append(_ entry: PayabliPayInDiagnosticEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    var all: [PayabliPayInDiagnosticEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}
