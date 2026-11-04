import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A card's expiry is a month and a four-digit year. `capture`, `authorize` and `addPaymentMethod` refuse one the
/// wire can't carry or that has passed, with `VALIDATION_ERROR`, before anything is sent. The wire carries `MM/YY`.
@MainActor
final class PayInCardExpiryTests: XCTestCase {
    private enum Route: CaseIterable {
        case capture, authorize, store
    }

    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    override func tearDown() {
        PayInKeyStore.process.forgetHeld()
        super.tearDown()
    }

    // MARK: - Refused before sending

    func testAMonthOutsideOneToTwelveIsRefusedUnsentOnEveryRoute() async {
        for month in [0, 13] {
            for route in Route.allCases {
                await assertRefusedUnsent(month: month, year: 2030, on: route)
            }
        }
    }

    func testAYearThatIsNotFourDigitsIsRefusedUnsentOnEveryRoute() async {
        for year in [30, 20300] {
            for route in Route.allCases {
                await assertRefusedUnsent(month: 4, year: year, on: route)
            }
        }
    }

    func testAYearAfter2099IsRefusedUnsentOnEveryRoute() async {
        for route in Route.allCases {
            await assertRefusedUnsent(month: 1, year: 2100, on: route)
        }
    }

    func testLastMonthsExpiryIsRefusedUnsentOnEveryRoute() async {
        let last = Self.monthOffset(-1)
        for route in Route.allCases {
            await assertRefusedUnsent(month: last.month, year: last.year, on: route)
        }
    }

    func testTodayIsReadOnTheGregorianCalendarWhateverTheDeviceIsSetTo() {
        // On a device set to the Buddhist calendar the year reads 2569, and every card would be refused as expired.
        XCTAssertEqual(PayabliPayInCardData.expiryCalendar.identifier, .gregorian)
    }

    // MARK: - Accepted

    func testThisMonthsExpiryIsSentOnEveryRoute() async {
        let now = Self.monthOffset(0)
        for route in Route.allCases {
            await assertSent(month: now.month, year: now.year, on: route)
        }
    }

    func testDecember2099IsSentOnEveryRoute() async {
        for route in Route.allCases {
            await assertSent(month: 12, year: 2099, on: route)
        }
    }

    // MARK: - The wire

    func testAprilTwentyThirtyIsWrittenAsZeroFourSlashThirty() throws {
        let card = Self.card(month: 4, year: 2030)
        let capture = try PayInBodyWriter.captureFragment(.card(PayabliPayInPaymentMethod.Card(data: card)))
        let store = try PayInBodyWriter.storeFragment(.card(card))
        XCTAssertEqual(try Self.member("cardexp", of: capture.rawCopy()), "04/30")
        XCTAssertEqual(try Self.member("cardexp", of: store.rawCopy()), "04/30")
    }

    func testABankAccountBuiltWithoutASecCodeSendsWebOnCaptureAndStore() throws {
        let account = PayabliPayInBankAccountData(
            accountNumber: "123456789",
            routingNumber: "021000021",
            accountType: .checking,
            holderName: "Jane Doe"
        )
        XCTAssertNil(account.secCode)
        let capture = try PayInBodyWriter.captureFragment(.bankAccount(PayabliPayInPaymentMethod.BankAccount(
            data: account
        )))
        let store = try PayInBodyWriter.storeFragment(.bankAccount(account))
        XCTAssertEqual(try Self.member("achCode", of: capture.rawCopy()), "WEB")
        XCTAssertEqual(try Self.member("achCode", of: store.rawCopy()), "WEB")
    }

    // MARK: - Fixtures

    private func assertRefusedUnsent(
        month: Int,
        year: Int,
        on route: Route,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let refusal = await PayInFixture.failure(
            from: { try await send(Self.card(month: month, year: year), on: route, transport: transport) },
            file: file,
            line: line
        )
        XCTAssertEqual(transport.count, 0, "\(month)/\(year) reached the service on \(route)", file: file, line: line)
        XCTAssertEqual(
            (refusal as? any PayabliError)?.type,
            .validation,
            "\(month)/\(year) on \(route): \(String(describing: refusal))",
            file: file,
            line: line
        )
    }

    private func assertSent(
        month: Int,
        year: Int,
        on route: Route,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let transport = RecordingIdempotencyTransport(body: route == .store ? Self.stored : PayInFixture.approved)
        do {
            try await send(Self.card(month: month, year: year), on: route, transport: transport)
        } catch {
            XCTFail("\(month)/\(year) on \(route) was refused: \(error)", file: file, line: line)
        }
        XCTAssertEqual(transport.count, 1, "\(month)/\(year) wasn't sent on \(route)", file: file, line: line)
    }

    private func send(
        _ card: PayabliPayInCardData,
        on route: Route,
        transport: RecordingIdempotencyTransport
    ) async throws {
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let request = PayabliPayInRequest(
            paymentMethod: .card(PayabliPayInPaymentMethod.Card(data: card)),
            options: PayabliPayInRequestConfiguration(paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10))
        )
        switch route {
        case .capture: _ = try await flow.capture(request)
        case .authorize: _ = try await flow.authorize(request)
        case .store: _ = try await flow.addPaymentMethod(.card(card))
        }
    }

    private static func card(month: Int, year: Int) -> PayabliPayInCardData {
        PayabliPayInCardData(
            cardNumber: "4111111111111111",
            expiryMonth: month,
            expiryYear: year,
            securityCode: "999",
            holderName: "Jane Doe",
            postalCode: "12345"
        )
    }

    /// The month `offset` months from the current one, read from the clock the SDK reads.
    private static func monthOffset(_ offset: Int) -> (month: Int, year: Int) {
        let calendar = PayabliPayInCardData.expiryCalendar
        let date = calendar.date(byAdding: .month, value: offset, to: Date()) ?? Date()
        let parts = calendar.dateComponents([.year, .month], from: date)
        return (parts.month ?? 0, parts.year ?? 0)
    }

    private static func member(_ name: String, of bytes: [UInt8]) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any]
        return object?[name] as? String
    }

    private static let stored = Data("""
    {"responseText":"Success","isSuccess":true,"responseData":{"referenceId":"stored-123","resultCode":1,\
    "resultText":"Approved","methodReferenceId":"stored-123"}}
    """.utf8)
}
