import XCTest
import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils

#if canImport(ProximityReader)
import ProximityReader
#endif

/// A reader session that dies under a `.ready` session must leave the session
/// repairable.
///
/// Locking the phone during a charge tears the reader session down. Reporting
/// that failure without moving `sessionState` wedges the session permanently:
/// `charge()` begins with `reinitializeIfNeeded()`, which does nothing while the
/// state says `.ready`, so every later charge reuses the dead session.
@MainActor
final class PayabliTTPReaderSessionRecoveryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = Self.chargeStubHandler
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - The wedge

    func testSessionLevelReaderFailureLeavesTheSessionRepairable() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()
        provider.readingResult = .failure(Self.sessionLevelFailure)

        await XCTAssertThrowsErrorAsync(try await self.charge(ttp))

        XCTAssertEqual(
            ttp.sessionState, .sessionExpired,
            "a dead reader session must not still report .ready"
        )
    }

    func testSecondChargeSucceedsAfterASessionLevelFailure() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()
        let preparesAfterInitialize = provider.prepareReaderCalls

        provider.readingResult = .failure(Self.sessionLevelFailure)
        await XCTAssertThrowsErrorAsync(try await self.charge(ttp))

        // The reader works again; recovery is the SDK's job, not the caller's.
        provider.readingResult = .success(Self.cardReadResult)
        let result = try await charge(ttp)

        XCTAssertEqual(result.paymentTransId, Self.paymentTransId)
        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertGreaterThan(
            provider.prepareReaderCalls, preparesAfterInitialize,
            "recovery has to re-prepare the reader, or it is reusing the dead session"
        )
    }

    // MARK: - What must not invalidate

    func testCancelledTapKeepsTheSessionReady() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()
        let preparesAfterInitialize = provider.prepareReaderCalls

        provider.readingResult = .failure(Self.cancellationFailure)
        await XCTAssertThrowsErrorAsync(try await self.charge(ttp))

        XCTAssertEqual(
            ttp.sessionState, .ready,
            "dismissing the sheet must not cost a /config re-fetch and a reader re-prepare"
        )
        XCTAssertEqual(provider.prepareReaderCalls, preparesAfterInitialize)
    }

    func testCardReadFailureKeepsTheSessionReady() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()
        provider.readingResult = .failure(
            PayabliTTPError.nfcFailed(reason: "Charges: cardReadFailed")
        )

        await XCTAssertThrowsErrorAsync(try await self.charge(ttp))

        XCTAssertEqual(
            ttp.sessionState, .ready,
            "a card that failed to read says nothing about the session"
        )
    }

    // MARK: - Both classification tiers

    /// The typed tier. Reachable when the raw error propagates to the facade.
    #if canImport(ProximityReader)
    func testTypedReadErrorIsClassified() {
        XCTAssertTrue(readerFailureInvalidatesSession(PaymentCardReaderSession.ReadError.noReaderSession))
        XCTAssertTrue(readerFailureInvalidatesSession(PaymentCardReaderSession.ReadError.readerSessionExpired))
        XCTAssertTrue(readerFailureInvalidatesSession(PaymentCardReaderSession.ReadError.readerTokenExpired))
        XCTAssertTrue(readerFailureInvalidatesSession(PaymentCardReaderSession.ReadError.readerSessionAuthenticationError))

        XCTAssertFalse(readerFailureInvalidatesSession(PaymentCardReaderSession.ReadError.readCancelled))
        XCTAssertFalse(readerFailureInvalidatesSession(PaymentCardReaderSession.ReadError.cardReadFailed))
        XCTAssertFalse(readerFailureInvalidatesSession(PaymentCardReaderSession.ReadError.paymentCardDeclined))
        XCTAssertFalse(readerFailureInvalidatesSession(PaymentCardReaderSession.ReadError.readerSessionBusy))
    }
    #endif

    /// The text tier, which is the one that actually fires on device: the
    /// vendored reader rebuilds the error as a title plus a description and the
    /// typed value is gone by the time the facade sees it.
    func testStringifiedReadErrorIsClassified() {
        XCTAssertTrue(readerFailureInvalidatesSession(
            PayabliTTPError.nfcFailed(reason: "noReaderSession: no reader session available or the session isn't ready")
        ))
        XCTAssertTrue(readerFailureInvalidatesSession(
            PayabliTTPError.nfcFailed(reason: "Charges: readerSessionExpired")
        ))

        XCTAssertFalse(readerFailureInvalidatesSession(
            PayabliTTPError.nfcFailed(reason: "cancelled: user dismissed Tap to Pay sheet")
        ))
        XCTAssertFalse(readerFailureInvalidatesSession(
            PayabliTTPError.nfcFailed(reason: "Charges: Payment Card data missing or corrupt.")
        ))
    }

    /// `readerSessionBusy` shares the `readerSession` prefix with two names that
    /// do invalidate, so it is the case most likely to be swept up by a looser
    /// match. It is transient: the session is alive and busy.
    func testTransientSessionBusyIsNotAnInvalidation() {
        XCTAssertFalse(readerFailureInvalidatesSession(
            PayabliTTPError.nfcFailed(reason: "Charges: readerSessionBusy")
        ))
    }

    // MARK: - initialize() from a state it did not start in

    /// `initialize()` is the entry point a host is told to call again, so it has
    /// to work from wherever the session happens to be.
    ///
    /// Every transition it makes was being discarded, so from `.sessionExpired`
    /// it did all of its work — attestation, config, preparing the reader — and
    /// then left the state exactly where it found it. Success, reported as
    /// failure, with no way to tell them apart.
    func testInitializeRecoversFromAnExpiredSession() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()

        provider.readingResult = .failure(Self.sessionLevelFailure)
        await XCTAssertThrowsErrorAsync(try await self.charge(ttp))
        XCTAssertEqual(ttp.sessionState, .sessionExpired)

        provider.readingResult = .success(Self.cardReadResult)
        try await ttp.initialize()

        XCTAssertEqual(
            ttp.sessionState, .ready,
            "initialize() did its work but never moved the state"
        )
    }

    /// The same hole from the other direction: re-initializing a healthy session
    /// must leave it observably ready rather than relying on it already being so.
    func testInitializeFromReadyStaysReady() async throws {
        let (ttp, _, _) = try await makeReadyTTP()
        try await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .ready)
    }

    // MARK: - Error text reaching the host

    /// A host shows `localizedDescription`. When the facade re-wraps an error
    /// that is already a `PayabliTTPError`, that value becomes the whole enum
    /// printed back — case name, parentheses, and the inner string escaped —
    /// which is what a person then reads on screen.
    func testPrepareFailureKeepsTheAdapterMessage() async throws {
        let provider = MockTapToPayProvider()
        provider.prepareReaderResult = .failure(
            PayabliTTPError.readerSetupFailed(
                reason: "passcodeDisabled: Error that indicates the device doesn't have an active passcode."
            )
        )
        let ttp = makeTTP(provider: provider)

        do {
            try await ttp.initialize()
            XCTFail("expected initialize to fail")
        } catch {
            let shown = error.localizedDescription
            XCTAssertEqual(
                shown,
                "passcodeDisabled: Error that indicates the device doesn't have an active passcode."
            )
            XCTAssertFalse(shown.contains("readerSetupFailed("), "the enum itself leaked into the message")
            XCTAssertFalse(shown.contains("\\'"), "the inner string was escaped for display")
        }
    }

    func testChargeFailureKeepsTheReaderMessage() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()
        provider.readingResult = .failure(Self.sessionLevelFailure)

        do {
            _ = try await charge(ttp)
            XCTFail("expected the charge to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "noReaderSession: no reader session available or the session isn't ready"
            )
        }
    }

    // MARK: - Fixtures

    private static let paymentTransId = "ttp-txn-1"

    /// Shaped as the facade receives it on device: the vendored reader catches
    /// the ProximityReader error and keeps only `title: description`.
    private static let sessionLevelFailure = PayabliTTPError.nfcFailed(
        reason: "noReaderSession: no reader session available or the session isn't ready"
    )

    private static let cancellationFailure = PayabliTTPError.nfcFailed(
        reason: "\(FiservCardReader.cancellationReasonPrefix) user dismissed Tap to Pay sheet"
    )

    private static let cardReadResult = CardReadResult(
        provider: "mock",
        encryptedPayload: Data(),
        cardNetwork: "VISA",
        providerMetadata: [:],
        providerResponseJSON: Data("{}".utf8)
    )

    /// Bounded, so a regression that wedges the charge path fails on the bound
    /// with a message naming it, rather than running out the suite's clock.
    private func charge(_ ttp: PayabliTTP) async throws -> TransactionResult {
        try await withThrowingTaskGroup(of: TransactionResult.self) { group in
            group.addTask { @MainActor in
                try await ttp.charge(
                    type: .sale,
                    paymentDetails: PayabliTTPPaymentDetails(amount: 1, currency: "USD")
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                throw ChargeTimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw ChargeTimedOut() }
            return first
        }
    }

    private func makeTTP(provider: MockTapToPayProvider) -> PayabliTTP {
        PayabliTTP(
            config: PayabliConfig(accessToken: "seed_token", entryPoint: "e", environment: .sandbox),
            appId: "appid",
            provider: provider,
            attestation: MockDeviceAttestationService(),
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
    }

    /// A TTP that has been through `initialize()`, so it holds a `deviceId` and
    /// sits at `.ready` — the only state `charge()` runs from.
    private func makeReadyTTP() async throws -> (PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService) {
        let provider = MockTapToPayProvider()
        let attestation = MockDeviceAttestationService()
        let config = PayabliConfig(
            accessToken: "seed_token",
            entryPoint: "e",
            environment: .sandbox
        )
        let ttp = PayabliTTP(
            config: config,
            appId: "appid",
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        try await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .ready, "the fixture itself is broken if this fails")
        return (ttp, provider, attestation)
    }

    /// Answers `/config`, `/initiate` and `/update` by path. The suite's shared
    /// handler answers every path with a config envelope, which `/initiate`
    /// cannot decode.
    private static let chargeStubHandler: StubURLProtocol.Handler = { request in
        let path = request.url?.path ?? ""
        let body: [String: Any]

        if path.contains("/MoneyIn/initiate") {
            body = [
                "code": "A01",
                "data": ["paymentTransId": PayabliTTPReaderSessionRecoveryTests.paymentTransId]
            ]
        } else if path.contains("/MoneyIn/update/") {
            body = ["code": "A01", "data": ["paymentTransId": PayabliTTPReaderSessionRecoveryTests.paymentTransId]]
        } else {
            body = [
                "responseCode": 1,
                "isSuccess": true,
                "responseData": [
                    "credentials": [
                        "secretKey": "s",
                        "apiKey": "a",
                        "merchantId": "m",
                        "terminalId": "t"
                    ]
                ],
                "paymentToken": "payment_tok"
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: body)
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!,
            data
        )
    }
}

/// Distinguishes "the charge never returned" from "the charge threw", so a
/// wedge cannot be mistaken for the failure these tests expect.
private struct ChargeTimedOut: Error {}

// MARK: - Async throwing assertion

/// `XCTAssertThrowsError` has no async form, and an autoclosure cannot be
/// awaited, so the expression is taken as an async closure.
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "expected an error",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail(message, file: file, line: line)
    } catch {
        // Expected.
    }
}
