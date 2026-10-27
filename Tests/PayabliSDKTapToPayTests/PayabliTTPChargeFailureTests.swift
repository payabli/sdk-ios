import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// What a charge's failure tells a host: its own case, the words it shows, the
/// payment it names, and what it claims about the money. Where the session lands
/// is asserted only where the failure itself decides it.
@available(iOS 16.7, *)
@MainActor
final class PayabliTTPChargeFailureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = Self.chargeStubHandler
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Error text reaching the host

    /// A host shows `localizedDescription`. The adapter's own words reach it as
    /// written, never as an internal value printed back — case name,
    /// parentheses, and the inner string escaped.
    func testPrepareFailureKeepsTheAdapterMessage() async throws {
        let provider = MockTapToPayProvider()
        provider.prepareReaderResult = .failure(
            PayabliTTPError.readerSetupFailed(
                reason: "passcodeDisabled: Error that indicates the device doesn't have an active passcode."
            )
        )
        let ttp = try makeTTP(provider: provider)

        do {
            try await bounded { try await ttp.initialize() }
            XCTFail("expected initialize to fail")
        } catch {
            let adapterWords = "passcodeDisabled: Error that indicates the device doesn't have an active passcode."
            XCTAssertEqual((error as? TapToPayError)?.detail, adapterWords)
            let shown = error.localizedDescription
            XCTAssertTrue(shown.hasSuffix(adapterWords), shown)
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
            let readerWords = "noReaderSession: no reader session available or the session isn't ready"
            XCTAssertEqual((error as? TapToPayError)?.detail, readerWords)
            XCTAssertTrue(error.localizedDescription.hasSuffix(readerWords), error.localizedDescription)
        }
    }

    func testAReadFailureNamesThePaymentItBelongsTo() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()
        provider.readingResult = .failure(Self.sessionLevelFailure)

        let failure = try await chargeFailure(ttp)

        XCTAssertEqual(failure.paymentTransId, Self.paymentTransId)
        XCTAssertEqual(failure.capture, .unknown, "the processor may take the sale before the reader answers")
    }

    func testAnUntypedReadFailureNamesThePayment() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()
        provider.readingResult = .failure(URLError(.timedOut))

        let failure = try await chargeFailure(ttp)

        XCTAssertEqual(failure.type, .tapNotCompleted)
        XCTAssertEqual(failure.paymentTransId, Self.paymentTransId)
        XCTAssertEqual(failure.capture, .unknown)
    }

    func testAnUnsupportedOSDuringAReadKeepsItsCaseAndNamesThePayment() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()
        provider.readingResult = .failure(PayabliTTPError.readerOSVersionNotSupported())

        let failure = try await chargeFailure(ttp)

        XCTAssertEqual(failure.type, .deviceOSUnsupported, "the remedy is a different device, not a retry")
        XCTAssertEqual(failure.paymentTransId, Self.paymentTransId)
        XCTAssertEqual(failure.capture, .unknown, "the reader had been asked for a card")
    }

    /// A vendor refusal of the device ends the reader session, so the next charge re-arms a reader
    /// rather than reading against a dead one.
    func testAVendorRefusalOfTheDeviceDuringTheReadExpiresTheSession() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()
        provider.readingResult = .failure(PayabliTTPError.readerDeviceRefused(reason: "677: device refused"))

        let failure = try await chargeFailure(ttp)

        XCTAssertEqual(failure.type, .readerDeviceRefused)
        XCTAssertEqual(failure.paymentTransId, Self.paymentTransId)
        XCTAssertEqual(failure.capture, .unknown, "the processor may have taken the sale")
        XCTAssertEqual(ttp.sessionState, .sessionExpired)
    }

    /// The guard throws before the reader touches a card, so its code is not turned into an unconfirmed outcome.
    func testAReaderThatWasNotPreparedKeepsItsCaseAndChargedNothing() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()
        provider.readingResult = .failure(PayabliTTPError.guardFailed(reason: "Reader not prepared"))

        let failure = try await chargeFailure(ttp)

        XCTAssertEqual(failure.type, .sdkInternalError)
        XCTAssertEqual(failure.detail, "Reader not prepared")
        XCTAssertEqual(failure.paymentTransId, Self.paymentTransId)
        XCTAssertEqual(failure.capture, .notCharged, "the guard failed before a card was read")
    }

    // MARK: - A payment that cannot be opened

    /// A bare 404 from the opening names the paypoint's configuration, and the
    /// session lands where the merchant repairs it.
    func testABare404FromTheOpeningNamesThePaypointsConfigurationAndLandsRejected() async throws {
        let (ttp, _, _) = try await makeReadyTTP()
        StubURLProtocol.handler = { request in
            if request.url?.path.contains("/MoneyIn/initiate") == true {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Data()
                )
            }
            return try Self.chargeStubHandler(request)
        }

        let failure = try await chargeFailure(ttp)

        XCTAssertEqual(failure.type, .cardPresentNotEnabled, "\(failure)")
        XCTAssertEqual(ttp.sessionState, .failed(reason: .configurationRejected))
    }

    /// A declined opening is the payment's own answer, and nothing about the setup
    /// changed, so the session stays ready.
    func testADeclinedOpeningNamesThePaymentAndKeepsTheSessionReady() async throws {
        let (ttp, _, _) = try await makeReadyTTP()
        StubURLProtocol.handler = { request in
            if request.url?.path.contains("/MoneyIn/initiate") == true {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data(#"{"code":"D0001","reason":"not opened"}"#.utf8)
                )
            }
            return try Self.chargeStubHandler(request)
        }

        let failure = try await chargeFailure(ttp)

        XCTAssertEqual(failure.type, .paymentNotOpened, "\(failure)")
        XCTAssertEqual(ttp.sessionState, .ready)
    }

    // MARK: - Fixtures

    private func chargeFailure(_ ttp: PayabliTTP) async throws -> TapToPayError {
        do {
            _ = try await charge(ttp)
        } catch let failure as TapToPayError {
            return failure
        }
        XCTFail("expected the charge to fail")
        throw CancellationError()
    }

    private static let paymentTransId = "ttp-txn-1"

    /// Shaped as the facade receives it on device: the vendored reader catches
    /// the ProximityReader error and keeps only `title: description`.
    private static let sessionLevelFailure = PayabliTTPError.nfcFailed(
        reason: "noReaderSession: no reader session available or the session isn't ready"
    )

    private func charge(_ ttp: PayabliTTP) async throws -> TransactionResult {
        try await bounded {
            try await ttp.charge(
                paymentDetails: PayabliTTPPaymentDetails(amount: 1, currency: "USD")
            )
        }
    }

    /// How long a call may take before it is treated as never returning. Sized
    /// for the slowest machine that runs this, not the fastest: an existing test
    /// in this suite takes eighteen seconds on CI and milliseconds locally.
    private var boundSeconds: UInt64 {
        60
    }

    /// Every SDK call in this file goes through here: a wedge's failure mode is
    /// not returning, and an unbounded one costs a CI job instead of going red.
    /// Not a task group, which would await work the deadline cannot cancel.
    private func bounded<T: Sendable>(
        _ work: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let once = ResumeOnce()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let workTask = Task { @MainActor in
                do {
                    let value = try await work()
                    if !once.done {
                        once.done = true
                        continuation.resume(returning: value)
                    }
                } catch {
                    if !once.done {
                        once.done = true
                        continuation.resume(throwing: error)
                    }
                }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: boundSeconds * 1_000_000_000)
                if !once.done {
                    once.done = true
                    continuation.resume(throwing: ChargeTimedOut())
                }
                workTask.cancel()
            }
        }
    }

    private func makeTTP(provider: some TapToPayProvider) throws -> PayabliTTP {
        PayabliTTP(
            config: try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
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
        let config = try PayabliConfig(
            entryPoint: "e",
            environment: .sandbox,

            tokenProvider: { "seed_token" }
        )
        let ttp = PayabliTTP(
            config: config,
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        try await bounded { try await ttp.initialize() }
        XCTAssertEqual(ttp.sessionState, .ready, "the fixture itself is broken if this fails")
        return (ttp, provider, attestation)
    }

    /// Answers `/config`, `/initiate` and `/update` by path. A handler that answers every path
    /// with a config envelope is one `/initiate` cannot decode.
    private static let chargeStubHandler: StubURLProtocol.Handler = { request in
        let path = request.url?.path ?? ""
        let body: [String: Any] = if path.contains("/MoneyIn/initiate") {
            [
                "code": "A01",
                "data": ["paymentTransId": PayabliTTPChargeFailureTests.paymentTransId]
            ]
        } else if path.contains("/MoneyIn/update/") {
            ["code": "A01", "data": ["paymentTransId": PayabliTTPChargeFailureTests.paymentTransId]]
        } else {
            [
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

/// Guards a continuation so the deadline and the work cannot both resume it.
/// Only touched from the main actor, which is where both racers run.
@MainActor
private final class ResumeOnce {
    var done = false
}
