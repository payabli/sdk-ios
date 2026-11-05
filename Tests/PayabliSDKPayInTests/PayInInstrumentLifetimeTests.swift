import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A card or bank account value outlives the call that sends it: the call writes from copies it overwrites,
/// and leaves the value's own digits for the next call, a declared retry included.
@MainActor
final class PayInInstrumentLifetimeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    override func tearDown() {
        PayInKeyStore.process.forgetHeld()
        super.tearDown()
    }

    func testTheSameCardIsSentInFullOnANewPaymentAndOnItsRetry() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let method = Self.card()

        _ = try await flow.capture(Self.request(method, .newPayment))
        _ = try await flow.capture(Self.request(method, .retry))

        XCTAssertEqual(transport.count, 2, "both calls reached the service")
        for body in transport.sentBodies {
            XCTAssertTrue(body.contains("4111111111111111"), "the card number went out whole on each call")
            XCTAssertTrue(body.contains("\"999\""), "the security code went out on each call")
        }
    }

    func testTheSameBankAccountIsSentInFullTwice() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let method = Self.bankAccount()

        _ = try await flow.capture(Self.request(method, .newPayment))
        _ = try await flow.capture(Self.request(method, .retry))

        XCTAssertEqual(transport.count, 2, "both calls reached the service")
        for body in transport.sentBodies {
            XCTAssertTrue(body.contains("123456789012"), "the account number went out whole on each call")
        }
    }

    func testASuccessLeavesTheValuesDigitsInPlace() async throws {
        let flow = PayInFixture.makeFlow(
            transport: RecordingIdempotencyTransport(body: PayInFixture.approved),
            key: "k1"
        )
        let card = Self.card()
        let bank = Self.bankAccount()

        _ = try await flow.capture(Self.request(card, .newPayment, reference: "p-card"))
        _ = try await flow.capture(Self.request(bank, .newPayment, reference: "p-bank"))

        Self.assertIntact(card, bank)
    }

    func testARefusalBeforeSendingLeavesTheValuesDigitsInPlace() async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let card = Self.card()
        let bank = Self.bankAccount()

        _ = await PayInFixture.failure { _ = try await flow.capture(Self.request(card, .retry, reference: nil)) }
        _ = await PayInFixture.failure { _ = try await flow.capture(Self.request(bank, .retry, reference: nil)) }

        XCTAssertEqual(transport.count, 0, "the refusal came before sending")
        Self.assertIntact(card, bank)
    }

    func testAThrownFailureLeavesTheValuesDigitsInPlace() async {
        let transport = RecordingIdempotencyTransport(failure: URLError(.notConnectedToInternet))
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let card = Self.card()
        let bank = Self.bankAccount()

        _ = await PayInFixture.failure { _ = try await flow.capture(Self.request(card, .newPayment, reference: "p-card")) }
        _ = await PayInFixture.failure { _ = try await flow.capture(Self.request(bank, .newPayment, reference: "p-bank")) }

        XCTAssertEqual(transport.count, 2, "both calls reached the transport and failed there")
        Self.assertIntact(card, bank)
    }

    func testEachCallsCopiesAreOverwrittenWhenTheSameCardIsSentTwice() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let copies = DigitCopies.recording(flow)
        let method = Self.card()

        _ = try await flow.capture(Self.request(method, .newPayment))
        _ = try await flow.capture(Self.request(method, .retry))

        XCTAssertEqual(transport.count, 2, "both calls reached the service")
        copies.assertAllOverwritten(expected: 4)
    }

    func testASuccessOverwritesTheCallsCopies() async throws {
        let flow = PayInFixture.makeFlow(
            transport: RecordingIdempotencyTransport(body: PayInFixture.approved),
            key: "k1"
        )
        let copies = DigitCopies.recording(flow)

        _ = try await flow.capture(Self.request(Self.card(), .newPayment, reference: "p-card"))
        _ = try await flow.capture(Self.request(Self.bankAccount(), .newPayment, reference: "p-bank"))

        copies.assertAllOverwritten(expected: 3)
    }

    func testASuccessfulAuthorizationOverwritesTheCallsCopies() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let copies = DigitCopies.recording(flow)

        _ = try await flow.authorize(Self.request(Self.card(), .newPayment, reference: "p-card"))

        XCTAssertEqual(transport.count, 1, "the authorization reached the service")
        copies.assertAllOverwritten(expected: 2)
    }

    func testARefusalBeforeSendingOverwritesTheCallsCopies() async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let copies = DigitCopies.recording(flow)

        _ = await PayInFixture.failure { _ = try await flow.capture(Self.request(Self.card(), .retry, reference: nil)) }
        _ = await PayInFixture.failure {
            _ = try await flow.authorize(Self.request(Self.bankAccount(), .retry, reference: nil))
        }

        XCTAssertEqual(transport.count, 0, "the refusal came before sending")
        copies.assertAllOverwritten(expected: 3)
    }

    func testAThrownFailureOverwritesTheCallsCopies() async {
        let transport = RecordingIdempotencyTransport(failure: URLError(.notConnectedToInternet))
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let copies = DigitCopies.recording(flow)

        _ = await PayInFixture.failure {
            _ = try await flow.authorize(Self.request(Self.card(), .newPayment, reference: "p-card"))
        }
        _ = await PayInFixture.failure {
            _ = try await flow.capture(Self.request(Self.bankAccount(), .newPayment, reference: "p-bank"))
        }

        XCTAssertEqual(transport.count, 2, "both calls reached the transport and failed there")
        copies.assertAllOverwritten(expected: 3)
    }

    func testStoringACardAndABankAccountOverwritesTheCallsCopiesAndLeavesTheValues() async throws {
        let transport = RecordingIdempotencyTransport(body: Self.stored)
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let copies = DigitCopies.recording(flow)
        guard case let .card(card) = Self.card(), case let .bankAccount(bank) = Self.bankAccount() else {
            return XCTFail("fixture shapes changed")
        }

        _ = try await flow.storeMethod(PayabliPayInStoreRequest(instrument: .card(card.data), options: PayabliPayInStoreOptions()))
        _ = try await flow.storeMethod(PayabliPayInStoreRequest(instrument: .bankAccount(bank.data), options: PayabliPayInStoreOptions()))

        XCTAssertEqual(transport.count, 2, "both calls reached the service")
        for body in transport.sentBodies {
            XCTAssertTrue(
                body.contains("4111111111111111") || body.contains("123456789012"),
                "each stored value went out whole"
            )
        }
        copies.assertAllOverwritten(expected: 3)
        Self.assertIntact(.card(card), .bankAccount(bank))
    }

    func testARefusedStorageCallOverwritesItsCopiesAndLeavesTheValues() async {
        let transport = RecordingIdempotencyTransport(body: Self.stored)
        let flow = PayabliPayIn(entryPoint: " ", environment: .sandbox, transport: transport)
        let copies = DigitCopies.recording(flow)
        guard case let .card(card) = Self.card(), case let .bankAccount(bank) = Self.bankAccount() else {
            return XCTFail("fixture shapes changed")
        }

        _ = await PayInFixture.failure { _ = try await flow.storeMethod(PayabliPayInStoreRequest(
            instrument: .card(card.data),
            options: PayabliPayInStoreOptions()
        )) }
        _ = await PayInFixture.failure { _ = try await flow.storeMethod(PayabliPayInStoreRequest(
            instrument: .bankAccount(bank.data),
            options: PayabliPayInStoreOptions()
        )) }

        XCTAssertEqual(transport.count, 0, "the refusal came before sending")
        copies.assertAllOverwritten(expected: 3)
        Self.assertIntact(.card(card), .bankAccount(bank))
    }

    func testAThrownStorageFailureOverwritesItsCopiesAndLeavesTheValues() async {
        let transport = RecordingIdempotencyTransport(failure: URLError(.notConnectedToInternet))
        let flow = PayInFixture.makeFlow(transport: transport, key: "k1")
        let copies = DigitCopies.recording(flow)
        guard case let .card(card) = Self.card(), case let .bankAccount(bank) = Self.bankAccount() else {
            return XCTFail("fixture shapes changed")
        }

        _ = await PayInFixture.failure { _ = try await flow.storeMethod(PayabliPayInStoreRequest(
            instrument: .card(card.data),
            options: PayabliPayInStoreOptions()
        )) }
        _ = await PayInFixture.failure { _ = try await flow.storeMethod(PayabliPayInStoreRequest(
            instrument: .bankAccount(bank.data),
            options: PayabliPayInStoreOptions()
        )) }

        XCTAssertEqual(transport.count, 2, "both calls reached the transport and failed there")
        copies.assertAllOverwritten(expected: 3)
        Self.assertIntact(.card(card), .bankAccount(bank))
    }

    private static let stored = Data("""
    {"responseText":"Success","isSuccess":true,"responseData":{"referenceId":"stored-1","resultCode":1,\
    "resultText":"Approved","customerId":1,"methodReferenceId":"stored-1"}}
    """.utf8)

    private static func card() -> PayabliPayInPaymentMethod {
        .card(PayabliPayInPaymentMethod.Card(
            data: PayabliPayInCardData(
                cardNumber: "4111 1111 1111 1111",
                expiryMonth: 2,
                expiryYear: 2030,
                securityCode: "999",
                holderName: "Jane Doe",
                postalCode: "12345"
            ),
            saveIfSuccess: false
        ))
    }

    private static func bankAccount() -> PayabliPayInPaymentMethod {
        .bankAccount(PayabliPayInPaymentMethod.BankAccount(
            data: PayabliPayInBankAccountData(
                accountNumber: "123456789012",
                routingNumber: "021000021",
                accountType: .checking,
                holderName: "Jane Doe"
            )
        ))
    }

    private static func request(
        _ method: PayabliPayInPaymentMethod,
        _ attempt: PayabliAttempt,
        reference: String? = "p1"
    ) -> PayabliPayInRequest {
        PayabliPayInRequest(
            paymentMethod: method,
            options: PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10),
                paymentReference: reference,
                attempt: attempt
            )
        )
    }

    /// Each of the value's own buffers still holds every digit it was built with.
    private static func assertIntact(
        _ card: PayabliPayInPaymentMethod,
        _ bank: PayabliPayInPaymentMethod,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .card(cardMethod) = card, case let .bankAccount(bankMethod) = bank else {
            return XCTFail("fixture shapes changed", file: file, line: line)
        }
        XCTAssertEqual(cardMethod.data.cardNumber.read(), Array("4111 1111 1111 1111".utf8), file: file, line: line)
        XCTAssertEqual(cardMethod.data.securityCode.read(), Array("999".utf8), file: file, line: line)
        XCTAssertEqual(bankMethod.data.accountNumber.read(), Array("123456789012".utf8), file: file, line: line)
    }
}

/// Every buffer a flow copies for a call, so a test can read each one after the call has returned.
private final class DigitCopies: @unchecked Sendable {
    private let lock = NSLock()
    private var copies: [SensitiveDigits] = []

    /// Records each copy `flow` makes, which it still makes the default way.
    ///
    /// - Parameter flow: the flow whose copies to record.
    /// - Returns: the recorder.
    @MainActor
    static func recording(_ flow: PayabliPayIn) -> DigitCopies {
        let recorder = DigitCopies()
        flow.copyDigits = { original in
            let copy = SensitiveDigits.copy(of: original)
            recorder.lock.lock()
            recorder.copies.append(copy)
            recorder.lock.unlock()
            return copy
        }
        return recorder
    }

    /// Each copy was closed and its bytes read zero.
    func assertAllOverwritten(expected: Int, file: StaticString = #filePath, line: UInt = #line) {
        lock.lock()
        let recorded = copies
        lock.unlock()
        XCTAssertEqual(recorded.count, expected, "one copy per digit field per call", file: file, line: line)
        for copy in recorded {
            XCTAssertTrue(copy.isWiped, "the call closed its copy", file: file, line: line)
            let bytes = copy.rawCopy()
            XCTAssertFalse(bytes.isEmpty, "the copy held digits", file: file, line: line)
            XCTAssertTrue(bytes.allSatisfy { $0 == SensitiveDigits.wipedByte }, "every byte overwritten", file: file, line: line)
        }
    }
}
