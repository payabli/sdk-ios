import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

final class ChargeKeyStoreTests: XCTestCase {
    private let clock = ManualChargeClock()
    private lazy var store = ChargeKeyStore(newKey: Self.counter(), now: { [clock] in clock.now })

    // MARK: - What a retry is handed

    func testADeclaredRetryClaimsTheHeldKeyAndIsReportedReused() throws {
        let first = try reserve(.newPayment)
        store.supersede(entry: "e", environment: .sandbox, key: first.key, arrivedAt: first.reservedAt)

        let retry = try reserve(.retry)

        XCTAssertEqual(retry.key, first.key)
        XCTAssertTrue(retry.reused)
        XCTAssertFalse(first.reused)
    }

    func testANewPaymentMintsItsOwnKeyWhileOneIsHeld() throws {
        let held = try endUnknown(reserve(.newPayment))

        let next = try reserve(.newPayment)

        XCTAssertNotEqual(next.key, held.key)
        XCTAssertFalse(next.reused)
    }

    func testANewPaymentThatSettlesLeavesTheHeldKeyForADeclaredRetry() throws {
        let held = try endUnknown(reserve(.newPayment))
        let next = try reserve(.newPayment)
        store.settle(entry: "e", environment: .sandbox, key: next.key)
        store.supersede(entry: "e", environment: .sandbox, key: next.key, arrivedAt: next.reservedAt)

        XCTAssertEqual(try reserve(.retry).key, held.key)
    }

    func testADeclaredRetryWithNothingHeldMints() throws {
        let retry = try reserve(.retry)

        XCTAssertFalse(retry.reused)
    }

    func testADeclaredRetryClaimsTheNewestUnresolvedKey() throws {
        _ = try endUnknown(reserve(.newPayment))
        let newer = try endUnknown(reserve(.newPayment))

        XCTAssertEqual(try reserve(.retry).key, newer.key)
    }

    func testAChargeEndingUnknownDropsTheOlderKey() throws {
        let older = try endUnknown(reserve(.newPayment))
        let newer = try endUnknown(reserve(.newPayment))
        store.settle(entry: "e", environment: .sandbox, key: newer.key)

        let retry = try reserve(.retry)

        XCTAssertNotEqual(retry.key, older.key)
        XCTAssertFalse(retry.reused)
    }

    func testASettledChargeSupersedesNothing() throws {
        let held = try endUnknown(reserve(.newPayment))
        let next = try reserve(.newPayment)
        store.settle(entry: "e", environment: .sandbox, key: next.key)

        store.supersede(entry: "e", environment: .sandbox, key: next.key, arrivedAt: next.reservedAt)

        XCTAssertEqual(try reserve(.retry).key, held.key)
    }

    func testASettleWhoseKeyIsNoLongerHeldLeavesTheHeldKeyAlone() throws {
        let held = try endUnknown(reserve(.newPayment))

        store.settle(entry: "e", environment: .sandbox, key: "not-held")

        XCTAssertEqual(try reserve(.retry).key, held.key)
    }

    // MARK: - Which payment a retry describes

    func testARetryDescribingAnotherPaymentIsRefusedAndTheHeldKeyStays() throws {
        let held = try endUnknown(reserve(.newPayment, amount: 10, serviceFee: 1, currency: "USD", invoice: "INV-1"))
        let others: [(Decimal, Decimal, String?, String?)] = [
            (11, 1, "USD", "INV-1"),
            (10, 2, "USD", "INV-1"),
            (10, 1, "CAD", "INV-1"),
            (10, 1, "USD", "INV-2")
        ]
        for (amount, fee, currency, invoice) in others {
            XCTAssertThrowsError(
                try reserve(.retry, amount: amount, serviceFee: fee, currency: currency, invoice: invoice)
            ) { error in
                XCTAssertEqual((error as? TapToPayError)?.type, .retryNotSamePayment)
            }
        }

        XCTAssertEqual(
            try reserve(.retry, amount: 10, serviceFee: 1, currency: "USD", invoice: "INV-1").key,
            held.key
        )
    }

    func testARetryTheServiceWouldChargeTheSameWayClaimsTheHeldKey() throws {
        let held = try endUnknown(reserve(.newPayment, amount: 10, currency: "usd"))

        let retry = try reserve(.retry, amount: 10.00, currency: " USD ", invoice: "INV-ADDED")

        XCTAssertEqual(retry.key, held.key)
    }

    func testAmountsAreComparedAtTheTwoPlacesTheReaderCharges() throws {
        let held = try endUnknown(reserve(.newPayment, amount: Self.decimal("10.005"), serviceFee: 0.5))

        XCTAssertEqual(
            try reserve(.retry, amount: 10, serviceFee: Self.decimal("0.499")).key,
            held.key,
            "10.005 is charged as 10.00"
        )
        XCTAssertThrowsError(try reserve(.retry, amount: Self.decimal("10.01"), serviceFee: 0.5), "10.01 is another payment")
        XCTAssertThrowsError(try reserve(.retry, amount: Self.decimal("10.006"), serviceFee: 0.5), "10.006 is charged as 10.01")
    }

    func testTheReaderAndTheRetryCheckRoundAlike() {
        XCTAssertEqual(Self.decimal("10.005").roundedAsCharged, Self.decimal("10.00"))
        XCTAssertEqual(Self.decimal("10.015").roundedAsCharged, Self.decimal("10.02"))
        XCTAssertEqual(Self.decimal("10.006").roundedAsCharged, Self.decimal("10.01"))
    }

    func testAKeyHeldAgainKeepsThePaymentItWasFirstSentFor() throws {
        _ = try endUnknown(reserve(.newPayment, amount: 10, invoice: "INV-1"))
        _ = try endUnknown(reserve(.retry, amount: 10, invoice: "INV-1"))

        XCTAssertThrowsError(try reserve(.retry, amount: 10, invoice: "INV-2"))
    }

    // MARK: - Where a key belongs

    func testTwoEntryPointsHoldIndependentKeys() throws {
        let first = try endUnknown(reserve(.newPayment, entry: "a"), entry: "a")
        let second = try endUnknown(reserve(.newPayment, entry: "b"), entry: "b")
        store.settle(entry: "a", environment: .sandbox, key: first.key)

        XCTAssertFalse(try reserve(.retry, entry: "a").reused)
        XCTAssertEqual(try reserve(.retry, entry: "b").key, second.key)
    }

    func testASandboxKeyIsNotHandedToProduction() throws {
        _ = try endUnknown(reserve(.newPayment))

        let production = try store.reserve(
            entry: "e",
            environment: .production,
            attempt: .retry,
            description: Self.payment()
        )

        XCTAssertFalse(production.reused)
    }

    func testTwoTerminalsRetryingAtOnceShareOneKey() async throws {
        let shared = store
        let keys = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0 ..< 2 {
                group.addTask {
                    try shared.reserve(entry: "e", environment: .sandbox, attempt: .retry, description: Self.payment()).key
                }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }

        XCTAssertEqual(Set(keys).count, 1)
    }

    // MARK: - Whether a retry would be handed a held key

    func testARetryOfTheHeldSaleIsReportedHeldAndNothingIsReserved() throws {
        let held = try endUnknown(reserve(.newPayment))

        XCTAssertTrue(holdsRetry())
        XCTAssertTrue(holdsRetry(), "asking consumed the key")
        let retry = try reserve(.retry)
        XCTAssertEqual(retry.key, held.key)
        XCTAssertTrue(retry.reused)
    }

    func testAskingWhileTheKeyIsBeingSentLeavesItsSendCountAlone() throws {
        let sending = try reserve(.newPayment)
        clock.advance(by: payabliIdempotencyKeyMaxAge)

        XCTAssertTrue(holdsRetry(), "a key still being sent was aged out")
        store.supersede(entry: "e", environment: .sandbox, key: sending.key, arrivedAt: nil)

        XCTAssertFalse(holdsRetry(), "asking counted a send the key is still waiting on")
    }

    func testARetryOfAnotherSaleIsNotReportedHeld() throws {
        _ = try endUnknown(reserve(.newPayment))

        XCTAssertFalse(holdsRetry(amount: 2))
    }

    func testNothingHeldIsNotReportedHeld() {
        XCTAssertFalse(holdsRetry())
    }

    func testAKeyHeldForAnotherEntryPointOrEnvironmentIsNotReportedHeld() throws {
        _ = try endUnknown(reserve(.newPayment, entry: "a"), entry: "a")

        XCTAssertFalse(holdsRetry())
        XCTAssertFalse(store.holdsRetryOf(entry: "a", environment: .production, description: Self.payment()))
    }

    func testAnExpiredKeyIsNotReportedHeld() throws {
        _ = try endUnknown(reserve(.newPayment))
        clock.advance(by: payabliIdempotencyKeyMaxAge)

        XCTAssertFalse(holdsRetry())
    }

    // MARK: - How long a key is held

    func testAnExpiredKeyIsNotResent() throws {
        _ = try endUnknown(reserve(.newPayment))
        clock.advance(by: payabliIdempotencyKeyMaxAge)

        XCTAssertFalse(try reserve(.retry).reused)
    }

    func testTheBoundIsFourMinutes() {
        XCTAssertEqual(payabliIdempotencyKeyMaxAge, .seconds(240))
    }

    func testASendThatMayHaveArrivedRestartsItsKeysClockAndOneThatCannotDoesNot() throws {
        let held = try endUnknown(reserve(.newPayment))
        clock.advance(by: .seconds(180))
        let resent = try reserve(.retry)
        store.supersede(entry: "e", environment: .sandbox, key: resent.key, arrivedAt: resent.reservedAt)
        clock.advance(by: .seconds(120))

        let unsent = try reserve(.retry)
        XCTAssertEqual(unsent.key, held.key, "the resend did not restart the clock")
        store.supersede(entry: "e", environment: .sandbox, key: unsent.key, arrivedAt: nil)
        clock.advance(by: .seconds(180))

        XCTAssertFalse(try reserve(.retry).reused, "a send that never left restarted the clock")
    }

    func testAKeyStillBeingSentIsNotAgedOutAndAgesOutOnceItsSendEnds() throws {
        let sending = try reserve(.newPayment, entry: "a")
        clock.advance(by: .seconds(300))
        _ = try reserve(.newPayment, entry: "b")

        let resent = try reserve(.retry, entry: "a")
        XCTAssertEqual(resent.key, sending.key)

        store.supersede(entry: "a", environment: .sandbox, key: sending.key, arrivedAt: nil)
        store.supersede(entry: "a", environment: .sandbox, key: resent.key, arrivedAt: nil)
        XCTAssertFalse(try reserve(.retry, entry: "a").reused)
    }

    // MARK: - How many are held

    func testFourUnknownChargesOnOneEntryPointLeaveRoomForAnother() throws {
        for _ in 0 ..< 4 {
            _ = try endUnknown(reserve(.newPayment))
        }
        for entry in ["b", "c", "d"] {
            _ = try endUnknown(reserve(.newPayment, entry: entry), entry: entry)
        }

        XCTAssertNoThrow(try reserve(.newPayment))
    }

    func testAFullStoreRefusesRatherThanEvicting() throws {
        var held: [String: String] = [:]
        for entry in ["a", "b", "c", "d"] {
            held[entry] = try endUnknown(reserve(.newPayment, entry: entry), entry: entry).key
        }

        XCTAssertThrowsError(try reserve(.newPayment, entry: "e")) { error in
            XCTAssertEqual((error as? TapToPayError)?.type, .tooManyOpenCharges)
        }
        for (entry, key) in held {
            XCTAssertEqual(try reserve(.retry, entry: entry).key, key)
        }
    }

    func testAFullStoreClearsAsItsKeysAgeOut() throws {
        for entry in ["a", "b", "c", "d"] {
            _ = try endUnknown(reserve(.newPayment, entry: entry), entry: entry)
        }
        clock.advance(by: payabliIdempotencyKeyMaxAge)

        XCTAssertNoThrow(try reserve(.newPayment, entry: "e"))
    }

    // MARK: - What is printed

    func testNeitherTheKeyNorThePaymentIsPrinted() throws {
        let reservation = try reserve(.newPayment, amount: 12.34)

        let printed = "\(reservation) \(Self.payment(amount: 12.34)) \(String(reflecting: reservation))"

        XCTAssertFalse(printed.contains(reservation.key))
        XCTAssertFalse(printed.contains("12.34"))
    }

    // MARK: - Helpers

    private func reserve(
        _ attempt: PayabliAttempt,
        entry: String = "e",
        amount: Decimal = 1,
        serviceFee: Decimal = 0,
        currency: String? = nil,
        invoice: String? = nil
    ) throws -> ChargeKeyStore.Reservation {
        try store.reserve(
            entry: entry,
            environment: .sandbox,
            attempt: attempt,
            description: Self.payment(amount: amount, serviceFee: serviceFee, currency: currency, invoice: invoice)
        )
    }

    private func holdsRetry(amount: Decimal = 1) -> Bool {
        store.holdsRetryOf(entry: "e", environment: .sandbox, description: Self.payment(amount: amount))
    }

    /// Ends the send unknown, as a charge does once the card was asked for and no answer came.
    private func endUnknown(_ reservation: ChargeKeyStore.Reservation, entry: String = "e") -> ChargeKeyStore.Reservation {
        store.supersede(entry: entry, environment: .sandbox, key: reservation.key, arrivedAt: reservation.reservedAt)
        return reservation
    }

    private static func payment(
        amount: Decimal = 1,
        serviceFee: Decimal = 0,
        currency: String? = nil,
        invoice: String? = nil
    ) -> ChargeDescription {
        ChargeDescription(
            paymentDetails: PayabliTTPPaymentDetails(amount: amount, serviceFee: serviceFee, currency: currency),
            invoice: PayabliTTPInvoiceData(invoiceNumber: invoice)
        )
    }

    private static func decimal(_ text: String) -> Decimal {
        Decimal(string: text)!
    }

    private static func counter() -> @Sendable () -> String {
        let minted = MintCounter()
        return { minted.next() }
    }
}

final class ManualChargeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now

    var now: ContinuousClock.Instant {
        lock.withLock { instant }
    }

    func advance(by duration: Duration) {
        lock.withLock { instant += duration }
    }
}

private final class MintCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> String {
        lock.withLock {
            count += 1
            return "key-\(count)"
        }
    }
}
