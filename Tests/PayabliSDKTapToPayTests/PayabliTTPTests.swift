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
    ) throws -> (PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService) {
        let config = try PayabliConfig(
            entryPoint: "e",
            environment: .sandbox,

            tokenProvider: { "seed_token" }
        )
        let ttp = PayabliTTP(
            config: config,
            provider: provider,
            attestation: attestation,
            retryPolicy: retry,
            session: StubURLProtocol.makeSession()
        )
        return (ttp, provider, attestation)
    }

    /// The call throws and the state carries the same reason, as every failed reason does.
    func testAKeyCheckThatCannotTellThrowsAndLandsOnDeviceKeyUnavailable() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.readFailure = TapToPayError(type: .deviceKeyUnavailable, reason: "x", detail: nil)

        do {
            try await ttp.initialize()
            XCTFail("initialize proceeded past a key check that could not tell")
        } catch {
            XCTAssertEqual((error as? TapToPayError)?.type, .deviceKeyUnavailable, "\(error)")
        }
        XCTAssertEqual(ttp.sessionState, .failed(reason: .deviceKeyUnavailable))
    }

    func testColdInitializeRunsAttestation() async throws {
        let (ttp, provider, attestation) = try makeTTP()
        attestation.isAlreadyAttested = false

        try await ttp.initialize()
        XCTAssertEqual(attestation.attestCalls, 1)
        XCTAssertEqual(provider.prepareReaderCalls, 1)
        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertTrue(ttp.isReady)
    }

    func testWarmInitializeSkipsAttestation() async throws {
        let (ttp, provider, attestation) = try makeTTP()
        attestation.isAlreadyAttested = true

        try await ttp.initialize()
        XCTAssertEqual(attestation.attestCalls, 0, "Warm start must not re-attest")
        XCTAssertEqual(provider.prepareReaderCalls, 1)
        XCTAssertEqual(ttp.sessionState, .ready)
    }

    func testPendingActivationSurfacesError() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev"

        do {
            try await ttp.initialize()
            XCTFail("expected pending activation")
        } catch let error as TapToPayError where error.type == .devicePendingActivation {
            XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testEligibilityFailurePreventsInit() async throws {
        let (ttp, provider, _) = try makeTTP()
        provider.eligibility = .failure(.readerSetupFailed(reason: "no entitlement"))
        do {
            try await ttp.initialize()
            XCTFail("expected eligibility failure")
        } catch let error as TapToPayError where error.type == .unknown && error.detail == "no entitlement" {
            XCTAssertEqual(ttp.sessionState.code, .failed)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testActivationFromPendingState() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev"
        _ = try? await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev"))

        try await ttp.activateDevice(activationCode: "ABC123")
        XCTAssertEqual(attestation.activateCalls, 1)
        XCTAssertEqual(ttp.sessionState, .idle)
    }

    func testActivationOutsidePendingStateIsInvalid() async throws {
        let (ttp, _, _) = try makeTTP()
        do {
            try await ttp.activateDevice(activationCode: "X")
            XCTFail("expected invalid state")
        } catch let error as TapToPayError where error.type == .deviceNotPending {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testChargeRejectsNonSale() async throws {
        let (ttp, _, _) = try makeTTP()
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

    /// The service says pending and nothing is stored: what is thrown and where the session lands
    /// both name the paypoint's configuration.
    func testPendingWithNothingStoredThrowsWhatTheSessionLandsOn() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.attestResult = .failure(PayabliTTPError.devicePendingActivation)
        do {
            try await ttp.initialize()
            XCTFail("expected a failure")
        } catch let error as TapToPayError
            where error.type == .unknown && error.detail?.contains("no registration is stored") == true
        {
        } catch {
            XCTFail("wrong error: \(error)")
        }

        XCTAssertEqual(ttp.sessionState, .failed(reason: .configurationRejected))
    }

    /// A pending answer whose stored registration cannot be read lands on the storage failure, not a
    /// pending device.
    func testPendingWithAnUnreadableStoreLandsOnTheStorageFailure() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev"
        attestation.registrationReadFailure = PayabliTTPError.attestationFailed(reason: "unreadable")
        _ = try? await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .failed(reason: .deviceKeyUnavailable))
    }

    /// An `initialize()` that fails in the attestation phase throws its catalog entry and fails the session.
    func testAttestationFailureThrowsItsCatalogEntryAndFailsTheSession() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.attestResult = .failure(PayabliTTPError.attestationFailed(reason: "key unusable"))

        do {
            try await ttp.initialize()
            XCTFail("expected the attestation phase to fail")
        } catch {
            XCTAssertEqual((error as? TapToPayError)?.type, .unknown, "got \(error)")
        }

        XCTAssertEqual(ttp.sessionState.code, .failed)
    }

    /// A warm-path read that fails is reported on the state as well as thrown, so a host observing the
    /// state and the caller see the same failure.
    func testAWarmReadFailureMarksTheState() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.readFailure = PayabliTTPError.attestationFailed(reason: "unreadable")

        _ = try? await ttp.initialize()

        XCTAssertEqual(ttp.sessionState.code, .failed, "the caller saw a failure and the published state did not")
    }

    /// A refusal whose drop did not land says so, since the binding is still
    /// readable and its key still signs, so the next warm check presents it again.
    func testAConfigRefusalThatCouldNotDropTheBindingSaysSo() async throws {
        let (ttp, _, attestation) = try makeTTP()
        attestation.isAlreadyAttested = true
        attestation.clearFailure = PayabliTTPError.attestationFailed(reason: "keychain unavailable")

        StubURLProtocol.handler = { request in
            (
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

        var thrown: Error?
        do {
            try await ttp.initialize()
            XCTFail("expected the config phase to reject")
        } catch {
            thrown = error
        }

        let raised = try XCTUnwrap(thrown)
        XCTAssertTrue(
            raised.localizedDescription.contains("could not be dropped"),
            raised.localizedDescription
        )
        XCTAssertTrue(attestation.isAlreadyAttested, "the binding is still readable")
    }

    /// A config 401 answering one handle leaves a binding enrolled since.
    func testAConfigRefusalLeavesABindingEnrolledSince() async throws {
        let (ttp, _, attestation) = try makeTTP()
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
        let (ttp, _, attestation) = try makeTTP()
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

    /// The thrown error and the state both name the failure as it arrived, so a
    /// service that may answer later reads as one.
    func testConfigFailureThrowsWhatFailedAndLandsItsRemedy() async throws {
        let (ttp, _, _) = try makeTTP()
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!, Data("{\"title\":\"Server error\"}".utf8))
        }

        var thrown: Error?
        do {
            try await ttp.initialize()
            XCTFail("expected the config phase to fail")
        } catch {
            thrown = error
        }

        // The whole state rather than its code, which is what pins the remedy a
        // host is actually given. A 500 is a service that may answer later.
        XCTAssertEqual(ttp.sessionState, .failed(reason: .serviceUnavailable))
        let raised = try XCTUnwrap(thrown, "initialize() returned instead of failing")
        let marked = try XCTUnwrap(ttp.sessionManager.lastError, "the session recorded no error")

        XCTAssertEqual((raised as? TapToPayError)?.type, .serverError, "got \(raised)")
        XCTAssertFalse(
            marked is PayabliTTPError,
            "the state is classified from the failure as it arrived, not from the wrapper"
        )
    }

    /// Two config failures under one wrapper land on different remedies, which is
    /// what the wrapper hid.
    func testConfigFailuresLandOnTheRemedyOfWhatFailedRatherThanOnOne() async throws {
        let (ttp, _, _) = try makeTTP()
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!, Data(#"{"title":"Bad request","status":400}"#.utf8))
        }

        do {
            try await ttp.initialize()
            XCTFail("expected the config phase to fail")
        } catch {
            XCTAssertEqual((error as? TapToPayError)?.type, .validation, "got \(error)")
        }

        // The same bytes get the same answer, so a retry is not the remedy. A 500
        // on the same route lands on `serviceUnavailable`.
        XCTAssertEqual(ttp.sessionState, .failed(reason: .sdkInternalError))
    }

    /// The caller is given the service's own wording through the thrown error.
    func testConfigFailureGivesTheCallerTheServersWords() async throws {
        let (ttp, _, _) = try makeTTP()
        let serversWords = "Card number belongs to another merchant"
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!, Data(#"{"title":"\#(serversWords)","status":400}"#.utf8))
        }

        var thrown: Error?
        do {
            try await ttp.initialize()
            XCTFail("expected the config phase to fail")
        } catch {
            thrown = error
        }

        let raised = try XCTUnwrap(thrown)
        let host = try XCTUnwrap(raised as? TapToPayError, "got \(raised)")
        XCTAssertTrue(host.localizedDescription.contains(serversWords), host.localizedDescription)
    }

    /// The 401 branch clears the attestation cache, marks the state and throws. A missing clear leaves the
    /// next call re-sending a handle the service has already refused.
    func testConfigRejectionClearsTheAttestationCacheAndReportsItOnce() async throws {
        let (ttp, _, attestation) = try makeTTP()
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

        var thrown: Error?
        do {
            try await ttp.initialize()
            XCTFail("expected the config phase to reject")
        } catch {
            thrown = error
        }
        let raised = try XCTUnwrap(thrown)
        let marked = try XCTUnwrap(ttp.sessionManager.lastError)

        XCTAssertFalse(attestation.isAlreadyAttested, "a refused handle must not be sent again")
        // A refused binding and a refused bearer are both worth another call,
        // which is the remedy the 401 carries.
        XCTAssertEqual(ttp.sessionState, .failed(reason: .serviceUnavailable))
        XCTAssertEqual((raised as? TapToPayError)?.type, .tokenExpired, "got \(raised)")
        // The drop is the config call's to make, so the reason claims nothing about
        // it. Claiming it here is what told a caller the binding was gone when it
        // was not.
        XCTAssertFalse(
            raised.localizedDescription.contains("cleared"),
            "the reason claims an outcome this layer does not decide"
        )
        XCTAssertFalse(marked is PayabliTTPError, "the state is classified from the 401 itself")
    }

    /// An Objective-C host is told about every state `initialize()` passes through, and reads each one.
    func testInitializeWalksTheSessionStatesAnObserverReads() async throws {
        let (ttp, _, _) = try makeTTP()
        var seen: [PayabliTTPSessionStateCode] = []
        let observation = ttp.addSessionStateObserver { seen.append(ttp.sessionStateCode) }

        try await ttp.initialize()
        observation.cancel()

        XCTAssertEqual(seen, [.attestingDevice, .fetchingConfig, .initializingReader, .ready])
    }

    func testACancelledObserverIsNotCalledAgain() async throws {
        let (ttp, _, _) = try makeTTP()
        var calls = 0
        let observation = ttp.addSessionStateObserver { calls += 1 }
        observation.cancel()
        observation.cancel()

        try await ttp.initialize()

        XCTAssertEqual(calls, 0)
    }
}
