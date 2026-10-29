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

    func testTwoTerminalsRetryingAtOnceAreHandedTheKeyOnce() async throws {
        let held = try endUnknown(reserve(.newPayment))
        let shared = store
        let outcomes = await withTaskGroup(of: Result<String, Error>.self) { group in
            for _ in 0 ..< 2 {
                group.addTask {
                    Result {
                        try shared.reserve(entry: "e", environment: .sandbox, attempt: .retry, description: Self.payment()).key
                    }
                }
            }
            return await group.reduce(into: [Result<String, Error>]()) { $0.append($1) }
        }

        let keys = outcomes.compactMap { try? $0.get() }
        let refusals = outcomes.compactMap { outcome -> PayabliErrorType? in
            guard case let .failure(error) = outcome else { return nil }
            return (error as? TapToPayError)?.type
        }
        XCTAssertEqual(keys, [held.key])
        XCTAssertEqual(refusals, [.paymentReferenceOpen])
    }

    func testARetryOntoAKeyBeingSentIsRefusedAsOpenAndTheKeyStays() throws {
        let sending = try reserve(.newPayment)

        XCTAssertThrowsError(try reserve(.retry)) { error in
            XCTAssertEqual((error as? TapToPayError)?.type, .paymentReferenceOpen)
        }
        store.supersede(entry: "e", environment: .sandbox, key: sending.key, arrivedAt: sending.reservedAt)
        XCTAssertEqual(try reserve(.retry).key, sending.key)
    }

    func testANewPaymentIsNotRefusedWhileAKeyIsBeingSent() throws {
        let sending = try reserve(.newPayment)

        XCTAssertNotEqual(try reserve(.newPayment).key, sending.key)
    }

    // MARK: - What a refused retry finds held

    func testTheHeldKeysReadEveryKeyNotOnlyTheNewest() throws {
        _ = try endUnknown(reserve(.newPayment, amount: 1))
        _ = try reserve(.newPayment, amount: 2)

        let found = store.heldRetry(entry: "e", environment: .sandbox, description: Self.payment(amount: 1))

        XCTAssertEqual(found?.underWay, true, "the newest key's send is under way")
        XCTAssertEqual(found?.describesHeld, true, "the older sale's held key was not read")
        XCTAssertEqual(
            store.heldRetry(entry: "e", environment: .sandbox, description: Self.payment(amount: 3))?.describesHeld,
            false
        )
    }

    func testTheHeldKeysReadReservesNothingAndReadsOnlyItsEntryPoint() throws {
        let held = try endUnknown(reserve(.newPayment))

        XCTAssertNil(store.heldRetry(entry: "other", environment: .sandbox, description: Self.payment()))
        XCTAssertNil(store.heldRetry(entry: "e", environment: .production, description: Self.payment()))
        let found = store.heldRetry(entry: "e", environment: .sandbox, description: Self.payment())
        XCTAssertEqual(found?.underWay, false)
        XCTAssertEqual(found?.describesHeld, true)
        XCTAssertEqual(try reserve(.retry).key, held.key, "the read reserved the key")
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

        XCTAssertEqual(
            store.heldRetry(entry: "a", environment: .sandbox, description: Self.payment())?.underWay,
            true,
            "a key being sent aged out"
        )

        store.supersede(entry: "a", environment: .sandbox, key: sending.key, arrivedAt: nil)
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
