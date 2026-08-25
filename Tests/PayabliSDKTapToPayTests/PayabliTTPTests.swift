import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

@MainActor
final class PayabliTTPTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Default config stub — individual tests may override.
        StubURLProtocol.handler = Self.defaultStubHandler
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// Default handler returns a valid config envelope for any request so
    /// tests that don't care about the wire can still reach `.ready`.
    private static let defaultStubHandler: StubURLProtocol.Handler = { request in
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
        attestation: MockDeviceAttestationService = MockDeviceAttestationService(),
        retry: RetryPolicy = RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0)
    ) -> (PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService) {
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
            retryPolicy: retry,
            session: StubURLProtocol.makeSession()
        )
        return (ttp, provider, attestation)
    }

    func testColdInitializeRunsAttestation() async throws {
        let (ttp, provider, attestation) = makeTTP()
        attestation.isAlreadyAttested = false

        try await ttp.initialize()
        XCTAssertEqual(attestation.attestCalls, 1)
        XCTAssertEqual(provider.prepareReaderCalls, 1)
        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertTrue(ttp.isReady)
    }

    func testWarmInitializeSkipsAttestation() async throws {
        let (ttp, provider, attestation) = makeTTP()
        attestation.isAlreadyAttested = true

        try await ttp.initialize()
        XCTAssertEqual(attestation.attestCalls, 0, "Warm start must not re-attest")
        XCTAssertEqual(provider.prepareReaderCalls, 1)
        XCTAssertEqual(ttp.sessionState, .ready)
    }

    func testPendingActivationSurfacesError() async throws {
        let (ttp, _, attestation) = makeTTP()
        attestation.attestResult = .failure(PayabliTTPError.devicePendingActivation)

        do {
            try await ttp.initialize()
            XCTFail("expected pending activation")
        } catch PayabliTTPError.devicePendingActivation {
            XCTAssertEqual(ttp.sessionState, .pendingActivation)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testEligibilityFailurePreventsInit() async throws {
        let (ttp, provider, _) = makeTTP()
        provider.eligibility = .failure(.readerSetupFailed(reason: "no entitlement"))
        do {
            try await ttp.initialize()
            XCTFail("expected eligibility failure")
        } catch PayabliTTPError.readerSetupFailed {
            XCTAssertEqual(ttp.sessionState, .error)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testActivationFromPendingState() async throws {
        let (ttp, _, attestation) = makeTTP()
        attestation.attestResult = .failure(PayabliTTPError.devicePendingActivation)
        _ = try? await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .pendingActivation)

        try await ttp.activateDevice(activationCode: "ABC123")
        XCTAssertEqual(attestation.activateCalls, 1)
        XCTAssertEqual(ttp.sessionState, .idle)
    }

    func testActivationOutsidePendingStateIsInvalid() async throws {
        let (ttp, _, _) = makeTTP()
        do {
            try await ttp.activateDevice(activationCode: "X")
            XCTFail("expected invalid state")
        } catch PayabliTTPError.invalidState {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testChargeRejectsNonSale() async throws {
        let (ttp, _, _) = makeTTP()
        do {
            _ = try await ttp.charge(
                type: PayabliTTPPaymentType(rawValue: 99) ?? .sale,
                paymentDetails: PayabliTTPPaymentDetails(amount: 9.99)
            )
            // .sale is the only case in v1.0, so this test is defensive. Pass either way.
        } catch {
            // ok
        }
    }

    /// How long an event has to arrive before the test says it never did. Long
    /// enough that a loaded machine is not the reason, short enough that the
    /// failure is read rather than waited out.
    private static let eventWait: UInt64 = 2_000_000_000

    /// Starts reading the stream for the first event `match` accepts.
    ///
    /// Bounded, because an event that never arrives would otherwise leave the
    /// reader awaiting forever, and a missing event has to fail a test rather
    /// than hang it.
    private func collect(
        from stream: AsyncStream<PayabliTTPEvent>,
        match: @escaping @Sendable (PayabliTTPEvent) -> String?
    ) -> Task<String?, Never> {
        Task {
            for await event in stream {
                if let found = match(event) {
                    return found
                }
            }
            return nil
        }
    }

    private func value(of collector: Task<String?, Never>, named name: String) async throws -> String {
        let deadline = Task {
            // A cancelled sleep throws, and swallowing that would cancel the
            // collector after it had already answered.
            guard (try? await Task.sleep(nanoseconds: Self.eventWait)) != nil else { return }
            collector.cancel()
        }
        let found = await collector.value
        deadline.cancel()
        return try XCTUnwrap(found, "no \(name) event arrived")
    }

    /// An `initialize()` that fails in the attestation phase says so on the event
    /// stream, which was silent before, and says it without repeating the reason.
    func testAttestationFailureEmitsAnEventNamingThePhase() async throws {
        let (ttp, _, attestation) = makeTTP()
        attestation.attestResult = .failure(PayabliTTPError.attestationFailed(reason: "key unusable"))
        let stream = ttp.events()

        let collector = collect(from: stream) { event in
            if case let .attestationFailed(error) = event {
                return error
            }
            return nil
        }

        _ = try? await ttp.initialize()
        let reported = try await value(of: collector, named: "attestationFailed")

        // The phase, not the sentence: a reason on this case is the SDK's words on
        // one path and the service's on another, so none of them travel.
        XCTAssertEqual(reported, "attestationFailed")
        XCTAssertFalse(reported.contains("key unusable"), reported)
        XCTAssertEqual(ttp.sessionState, .error)
    }

    /// A warm-path read that fails is reported through all three channels, not just
    /// the thrown one. Read outside the phase's own handling it threw out of
    /// `initialize()` while the published state stayed where `reset()` left it, so a
    /// host observing `state` saw an idle session and a caller saw a failure.
    func testAWarmReadFailureMarksTheStateAndEmitsTheEvent() async throws {
        let (ttp, _, attestation) = makeTTP()
        attestation.readFailure = PayabliTTPError.attestationFailed(reason: "unreadable")
        let stream = ttp.events()

        let collector = collect(from: stream) { event in
            if case let .attestationFailed(error) = event {
                return error
            }
            return nil
        }

        _ = try? await ttp.initialize()
        let reported = try await value(of: collector, named: "attestationFailed")

        XCTAssertEqual(reported, "attestationFailed")
        XCTAssertEqual(ttp.sessionState, .error, "the caller saw a failure and the published state did not")
    }

    /// A config 401 answering one handle leaves a binding enrolled since.
    func testAConfigRefusalLeavesABindingEnrolledSince() async throws {
        let (ttp, _, attestation) = makeTTP()
        attestation.isAlreadyAttested = true
        attestation.bindings = [MockDeviceAttestationService.anyEntry: "dev_old"]

        StubURLProtocol.handler = { request in
            // Enrolled again while the config request is in flight.
            attestation.bindings = [MockDeviceAttestationService.anyEntry: "dev_new"]
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(
                    #"{"isSuccess":false,"responseText":"revoked","responseData":{"resultCode":401,"resultText":"revoked"}}"#
                        .utf8
                )
            )
        }

        _ = try? await ttp.initialize()

        XCTAssertEqual(
            try attestation.cachedDeviceId(for: "e"),
            "dev_new",
            "the binding enrolled while the request was in flight was cleared by a refusal about the older one"
        )
    }

    /// A charge names the binding held when it is sent, not the one held when the
    /// session was built.
    func testAChargeSendsTheBindingHeldWhenItIsSent() async throws {
        let (ttp, _, attestation) = makeTTP()
        attestation.bindings = [MockDeviceAttestationService.anyEntry: "dev_old"]

        let sent = BodyBox()
        StubURLProtocol.handler = { request in
            guard request.url?.path.contains("MoneyIn/initiate") == true else {
                return try Self.defaultStubHandler(request)
            }
            sent.append(request.payabliTestBody)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"isSuccess":false,"responseText":"declined","responseData":0}"#.utf8)
            )
        }

        try await ttp.initialize()
        attestation.bindings = [MockDeviceAttestationService.anyEntry: "dev_new"]

        _ = try? await ttp.charge(
            type: .sale,
            paymentDetails: PayabliTTPPaymentDetails(amount: 1.00)
        )

        let body = try XCTUnwrap(sent.values.first ?? nil, "no initiate request was sent")
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("dev_new"), text)
        XCTAssertFalse(text.contains("dev_old"), "a handle captured during initialize() was sent")
    }

    /// The event, the published state and the thrown error carry one value, so a
    /// reader comparing a screen against a log sees the same failure twice.
    func testConfigFailureEmitsAnEventAndMarksWhatItThrows() async throws {
        let (ttp, _, _) = makeTTP()
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!, Data("{\"title\":\"Server error\"}".utf8))
        }
        let stream = ttp.events()

        let collector = collect(from: stream) { event in
            if case let .configFailed(error) = event {
                return error
            }
            return nil
        }

        var thrown: Error?
        do {
            try await ttp.initialize()
            XCTFail("expected the config phase to fail")
        } catch {
            thrown = error
        }
        let reported = try await value(of: collector, named: "configFailed")

        XCTAssertEqual(ttp.sessionState, .error)
        let raised = try XCTUnwrap(thrown, "initialize() returned instead of failing")
        let marked = try XCTUnwrap(ttp.sessionManager.lastError, "the session recorded no error")

        XCTAssertEqual(reported, ErrorSummary.of(raised), "the event must summarise what was thrown")
        XCTAssertEqual(
            String(describing: marked),
            String(describing: raised),
            "the published state must hold what was thrown"
        )
    }

    /// An event payload is forwarded to whatever logging a host app has, so the
    /// service's own wording must not ride along in one. The caller still gets it,
    /// through the thrown error.
    func testConfigFailureEventCarriesTheCodeRatherThanTheServersWords() async throws {
        let (ttp, _, _) = makeTTP()
        let serversWords = "Card number belongs to another merchant"
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!, Data(#"{"title":"\#(serversWords)","status":400}"#.utf8))
        }
        let stream = ttp.events()

        let collector = collect(from: stream) { event in
            if case let .configFailed(error) = event {
                return error
            }
            return nil
        }

        var thrown: Error?
        do {
            try await ttp.initialize()
            XCTFail("expected the config phase to fail")
        } catch {
            thrown = error
        }
        let reported = try await value(of: collector, named: "configFailed")

        XCTAssertEqual(reported, "configFailed")
        XCTAssertFalse(reported.contains(serversWords), reported)

        // The other half of the split: what the event withholds, the caller gets.
        let raised = try XCTUnwrap(thrown)
        XCTAssertTrue(raised.localizedDescription.contains(serversWords), raised.localizedDescription)
        XCTAssertTrue(raised is PayabliTTPError, "the bridges read the domain of this type")
    }

    /// The 401 branch does four things and had a test for none of them: it clears
    /// the attestation cache, marks, emits and throws. A missing clear leaves the
    /// next call re-sending a handle the service has already refused.
    func testConfigRejectionClearsTheAttestationCacheAndReportsItOnce() async throws {
        let (ttp, _, attestation) = makeTTP()
        attestation.isAlreadyAttested = true
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(
                    #"{"isSuccess":false,"responseText":"attestation revoked","responseData":{"resultCode":401,"resultText":"attestation revoked"}}"#
                        .utf8
                )
            )
        }
        let stream = ttp.events()

        let collector = collect(from: stream) { event in
            if case let .configFailed(error) = event {
                return error
            }
            return nil
        }

        var thrown: Error?
        do {
            try await ttp.initialize()
            XCTFail("expected the config phase to reject")
        } catch {
            thrown = error
        }
        let reported = try await value(of: collector, named: "configFailed")
        let raised = try XCTUnwrap(thrown)
        let marked = try XCTUnwrap(ttp.sessionManager.lastError)

        XCTAssertFalse(attestation.isAlreadyAttested, "a refused handle must not be sent again")
        XCTAssertEqual(ttp.sessionState, .error)
        XCTAssertEqual(reported, "configFailed")
        XCTAssertTrue(raised.localizedDescription.contains("401"), raised.localizedDescription)
        // The drop is the config call's to make, so the reason claims nothing about
        // it. Claiming it here is what told a caller the binding was gone when it
        // was not.
        XCTAssertFalse(
            raised.localizedDescription.contains("cleared"),
            "the reason claims an outcome this layer does not decide"
        )
        XCTAssertEqual(String(describing: marked), String(describing: raised))
    }

    /// The rule reaches the events that predate it. An activation failure's reason
    /// can be the service's own, since the decline body is where it comes from.
    func testActivationFailureEventNamesTheCaseWithoutItsReason() async throws {
        let (ttp, _, attestation) = makeTTP()
        let serversWords = "Device belongs to another merchant"
        attestation.attestResult = .failure(PayabliTTPError.devicePendingActivation)
        _ = try? await ttp.initialize()
        attestation.activationResult = .failure(
            PayabliTTPError.activationFailed(reason: serversWords)
        )
        let stream = ttp.events()

        let collector = collect(from: stream) { event in
            if case let .activationFailed(error) = event {
                return error
            }
            return nil
        }

        _ = try? await ttp.activateDevice(activationCode: "ABC123")
        let reported = try await value(of: collector, named: "activationFailed")

        XCTAssertEqual(reported, "activationFailed")
        XCTAssertFalse(reported.contains(serversWords), reported)
    }

    func testEventsStreamDeliversLifecycle() async throws {
        let (ttp, _, _) = makeTTP()
        let stream = ttp.events()

        let collector = Task {
            var events: [String] = []
            for await event in stream {
                switch event {
                case .attestationStarted: events.append("att-start")
                case .attestationCompleted: events.append("att-done")
                case .readerInitializing: events.append("rdy-init")
                case .readerReady: events.append("rdy-ready")
                    return events
                default: break
                }
            }
            return events
        }

        try await ttp.initialize()
        let received = await collector.value

        XCTAssertTrue(received.contains("att-start"))
        XCTAssertTrue(received.contains("att-done"))
        XCTAssertTrue(received.contains("rdy-init"))
        XCTAssertTrue(received.contains("rdy-ready"))
    }
}
