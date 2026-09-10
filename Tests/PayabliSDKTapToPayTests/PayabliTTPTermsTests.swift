import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

@MainActor
final class PayabliTTPTermsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = Self.stubHandler
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// Returns a config envelope for any request, so a test reaches the reader
    /// phase without caring about the wire.
    private static let stubHandler: StubURLProtocol.Handler = { request in
        let body: [String: Any] = [
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
        let data = try JSONSerialization.data(withJSONObject: body)
        return (HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!, data)
    }

    private func makeTTP(
        provider: MockTapToPayProvider = MockTapToPayProvider(),
        attestation: MockDeviceAttestationService = MockDeviceAttestationService()
    ) throws -> (PayabliTTP, MockTapToPayProvider) {
        let config = try PayabliConfig(
            entryPoint: "e",
            environment: .sandbox,
            tokenProvider: { "seed_token" }
        )
        let ttp = PayabliTTP(
            config: config,
            appId: "appid",
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        return (ttp, provider)
    }

    // MARK: - The facade forwards, and adds nothing

    func testReportsAcceptedWhenTheProviderDoes() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .success(true)

        let accepted = try await ttp.areTermsAccepted()

        XCTAssertTrue(accepted)
        XCTAssertEqual(provider.areTermsAcceptedCalls, 1)
    }

    func testReportsNotAcceptedWhenTheProviderDoes() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .success(false)

        let accepted = try await ttp.areTermsAccepted()

        XCTAssertFalse(accepted)
    }

    /// A reader that cannot answer is a different outcome from one answering
    /// "not accepted", and a host showing a terms screen has to tell them apart.
    func testAReaderThatCannotAnswerThrowsRatherThanReportingNotAccepted() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .failure(
            PayabliTTPError.readerSetupFailed(reason: "Reader not prepared")
        )

        do {
            _ = try await ttp.areTermsAccepted()
            XCTFail("expected the provider's failure to surface")
        } catch let error as PayabliTTPError {
            guard case .readerSetupFailed = error else {
                return XCTFail("expected readerSetupFailed, got \(error)")
            }
        }
    }

    /// The question is asked on every call. Acceptance is granted and withdrawn
    /// outside this process, so an answer the SDK remembered would go stale with
    /// nothing failing.
    func testAsksThePlatformEveryTimeRatherThanCaching() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .success(false)
        _ = try await ttp.areTermsAccepted()

        provider.areTermsAcceptedResult = .success(true)
        let second = try await ttp.areTermsAccepted()

        XCTAssertTrue(second)
        XCTAssertEqual(provider.areTermsAcceptedCalls, 2)
    }

    // MARK: - The guarantee the feature rests on

    /// The facade puts no state guard in front of the question, and this is what
    /// holds it there. A provider that reports unaccepted terms leaves the session
    /// outside `.ready`, which is the one moment a host needs the answer; a guard
    /// on `sessionState == .ready` would refuse exactly then.
    ///
    /// Driven through the mock. The contract lets a provider report unaccepted
    /// terms; no shipped provider does yet, because `prepareReader()` still
    /// presents the sheet itself rather than reporting.
    func testTheQuestionIsAnswerableWhenTheSessionIsNotReady() async throws {
        let (ttp, provider) = try makeTTP()
        provider.prepareReaderResult = .failure(PayabliTTPError.termsNotAccepted)
        provider.areTermsAcceptedResult = .success(false)

        do {
            try await ttp.initialize()
            XCTFail("expected initialize to report unaccepted terms")
        } catch let error as PayabliTTPError {
            guard case .termsNotAccepted = error else {
                return XCTFail("expected termsNotAccepted, got \(error)")
            }
        }

        XCTAssertNotEqual(ttp.sessionState, .ready)
        let accepted = try await ttp.areTermsAccepted()
        XCTAssertFalse(accepted)
    }

    // MARK: - What initialize reports

    /// Unaccepted terms is a session waiting on a person, not a session that failed. `error` would tell
    /// a host to give up on something one tap resolves, and `pendingActivation` is the precedent for
    /// saying so.
    func testInitializeReportsPendingTermsRatherThanAnError() async throws {
        let (ttp, provider) = try makeTTP()
        provider.prepareReaderResult = .failure(PayabliTTPError.termsNotAccepted)

        do {
            try await ttp.initialize()
            XCTFail("expected initialize to report unaccepted terms")
        } catch let error as PayabliTTPError {
            guard case .termsNotAccepted = error else {
                return XCTFail("expected termsNotAccepted, got \(error)")
            }
        }

        XCTAssertEqual(ttp.sessionState, .pendingTerms)
    }

    /// A host that watches events rather than state is told the same thing.
    func testInitializeEmitsTermsRequired() async throws {
        let (ttp, provider) = try makeTTP()
        provider.prepareReaderResult = .failure(PayabliTTPError.termsNotAccepted)

        let seen = Task { () -> Bool in
            for await event in ttp.events() where event.code == .termsRequired {
                return true
            }
            return false
        }

        _ = try? await ttp.initialize()

        let emitted = await seen.value
        XCTAssertTrue(emitted, "a host watching events is told what the session is waiting on")
    }

    /// Any other setup failure is still an error, so the terms path did not widen what it catches.
    func testAnOrdinarySetupFailureIsStillAnError() async throws {
        let (ttp, provider) = try makeTTP()
        provider.prepareReaderResult = .failure(
            PayabliTTPError.readerSetupFailed(reason: "no reader")
        )

        _ = try? await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .error)
    }

    // MARK: - Presenting them

    /// The member reaches the provider, which is the whole of what the facade owes: the sheet belongs
    /// to the platform and the reader is what presents it.
    func testPresentingReachesTheProvider() async throws {
        let (ttp, provider) = try makeTTP()

        try await ttp.presentTerms()

        XCTAssertEqual(provider.presentTermsCalls, 1)
    }

    /// Presenting is answerable outside `.ready` for the same reason asking is, and this is the moment
    /// that matters: a session stopped on unaccepted terms is exactly when a host presents them. A
    /// state guard would refuse the one call that resolves the state.
    func testPresentingIsReachableWhileTheSessionWaitsOnTerms() async throws {
        let (ttp, provider) = try makeTTP()
        provider.prepareReaderResult = .failure(PayabliTTPError.termsNotAccepted)

        _ = try? await ttp.initialize()
        XCTAssertNotEqual(ttp.sessionState, .ready)

        try await ttp.presentTerms()

        XCTAssertEqual(provider.presentTermsCalls, 1)
    }

    /// Returning says the sheet was shown and dismissed, never that acceptance was given. The platform
    /// is the only authority on that, so a host reads it by asking afterwards.
    func testPresentingDoesNotItselfMeanAccepted() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .success(false)

        try await ttp.presentTerms()

        let accepted = try await ttp.areTermsAccepted()
        XCTAssertFalse(accepted, "presenting the sheet is not the merchant accepting it")
    }

    /// A failure from the platform reaches the caller rather than being reported as a dismissal.
    func testAFailureToPresentIsRaised() async throws {
        let (ttp, provider) = try makeTTP()
        provider.presentTermsResult = .failure(
            PayabliTTPError.readerSetupFailed(reason: "Reader not prepared")
        )

        do {
            try await ttp.presentTerms()
            XCTFail("expected the failure to reach the caller")
        } catch let error as PayabliTTPError {
            guard case .readerSetupFailed = error else {
                return XCTFail("expected readerSetupFailed, got \(error)")
            }
        }
    }

    /// The loop the feature is: stopped on terms, present, initialize again, ready.
    func testTheSessionReachesReadyOnceTermsAreAccepted() async throws {
        let (ttp, provider) = try makeTTP()
        provider.prepareReaderResult = .failure(PayabliTTPError.termsNotAccepted)

        _ = try? await ttp.initialize()
        XCTAssertNotEqual(ttp.sessionState, .ready)

        try await ttp.presentTerms()
        provider.prepareReaderResult = .success(())

        try await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .ready)
    }

    // MARK: - ObjC companion

    func testObjCCompanionDeliversTheAnswer() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .success(true)

        let done = expectation(description: "completion")
        ttp.areTermsAccepted { accepted, error in
            XCTAssertTrue(accepted)
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 1)
    }

    /// The bridge every wrapper calls: three of them reach the sheet through this
    /// selector rather than the Swift member, so its success path is theirs.
    func testObjCCompanionPresentsAndReportsNoError() async throws {
        let (ttp, provider) = try makeTTP()

        let done = expectation(description: "completion")
        ttp.presentTerms { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 1)

        XCTAssertEqual(provider.presentTermsCalls, 1)
    }

    /// A failure crosses the bridge as an `NSError` in the SDK's own domain, so a
    /// wrapper can tell a reader that could not present from a merchant who
    /// declined. Its code is the taxonomy's, not a bridging invention.
    func testObjCCompanionReportsAFailureAsAnNSError() async throws {
        let (ttp, provider) = try makeTTP()
        provider.presentTermsResult = .failure(
            PayabliTTPError.readerSetupFailed(reason: "Reader not prepared")
        )

        let done = expectation(description: "completion")
        ttp.presentTerms { error in
            XCTAssertEqual(error?.domain, "com.payabli.ttp")
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 1)
    }

    /// `false` on the failure path is the bridging default, not an answer. An ObjC
    /// caller reading the flag without the error would treat a broken reader as an
    /// unaccepted merchant.
    func testObjCCompanionReportsFailureAsAnErrorAndNotAsNotAccepted() async throws {
        let (ttp, provider) = try makeTTP()
        provider.areTermsAcceptedResult = .failure(PayabliTTPError.termsNotAccepted)

        let done = expectation(description: "completion")
        ttp.areTermsAccepted { accepted, error in
            XCTAssertFalse(accepted)
            XCTAssertEqual(error?.domain, "com.payabli.ttp")
            XCTAssertEqual(error?.code, 14)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 1)
    }
}
