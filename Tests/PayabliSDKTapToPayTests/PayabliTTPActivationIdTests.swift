import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

@MainActor
final class PayabliTTPActivationIdTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeTTP(
        attestation: MockDeviceAttestationService = MockDeviceAttestationService()
    ) throws -> (PayabliTTP, MockDeviceAttestationService) {
        let config = try PayabliConfig(
            entryPoint: "e",
            environment: .sandbox,
            tokenProvider: { "seed_token" }
        )
        let ttp = PayabliTTP(
            config: config,
            provider: MockTapToPayProvider(),
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        return (ttp, attestation)
    }

    private static func respond(_ status: Int) -> StubURLProtocol.Handler {
        { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("{}".utf8)
            )
        }
    }

    func testARegistrationLeftPendingHandsOverItsId() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev_e"

        do {
            try await ttp.initialize()
            XCTFail("expected pending activation")
        } catch let error as TapToPayError where error.type == .devicePendingActivation {}

        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_e"))
    }

    func testAnEnrolledDeviceTheServiceStillHoldsPendingHandsOverItsBoundId() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.bindings = ["e": "dev_e"]
        StubURLProtocol.handler = Self.respond(403)

        _ = try? await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_e"))
    }

    /// A 403 is about the registration the request presented. One replaced while the request was in
    /// flight gets no id it was not answered for.
    func testAPendingAnswerAboutAReplacedRegistrationHandsOverNoId() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.bindings = ["e": "dev_old"]
        StubURLProtocol.handler = { request in
            attestation.bindings = ["e": "dev_new"]
            return try Self.respond(403)(request)
        }

        do {
            try await ttp.initialize()
            XCTFail("expected a failure")
        } catch let error as TapToPayError
            where error.type == .unknown && error.detail?.contains("registration changed") == true
        {
        } catch {
            XCTFail("wrong error: \(error)")
        }

        XCTAssertEqual(ttp.sessionState, .failed(reason: .serviceUnavailable))
        XCTAssertNil(ttp.activationId)
    }

    /// Removed rather than replaced: the request had a registration, so this is not a paypoint that
    /// never registered.
    func testAPendingAnswerAboutARemovedRegistrationAsksForAnotherInitialize() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.bindings = ["e": "dev_old"]
        StubURLProtocol.handler = { request in
            attestation.bindings = [:]
            return try Self.respond(403)(request)
        }

        do {
            try await ttp.initialize()
            XCTFail("expected a failure")
        } catch let error as TapToPayError
            where error.type == .unknown && error.detail?.contains("registration changed") == true
        {
        } catch {
            XCTFail("wrong error: \(error)")
        }

        XCTAssertEqual(ttp.sessionState, .failed(reason: .serviceUnavailable))
    }

    func testInitializingAgainLandsOnTheSameId() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev_e"
        _ = try? await ttp.initialize()
        attestation.pendingRegistration = nil
        StubURLProtocol.handler = Self.respond(403)

        _ = try? await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_e"))
    }

    /// With nothing registered there is no device to activate, so the remedy is the paypoint's. The
    /// error still names the refusal that happened.
    func testARefusalBeforeAnyRegistrationIsNotPendingActivation() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.attestResult = .failure(
            PayabliGenericError(type: .permissionDenied, reason: "Forbidden (403)")
        )

        do {
            try await ttp.initialize()
            XCTFail("expected the refusal")
        } catch let error as TapToPayError {
            XCTAssertEqual(error.type, .permissionDenied)
            XCTAssertEqual(error.reason, "Forbidden (403)")
        }

        XCTAssertEqual(ttp.sessionState, .failed(reason: .configurationRejected))
    }

    func testPendingWithAStoreThatCannotBeReadThrowsWhatTheSessionLandsOn() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev_e"
        attestation.registrationReadFailure = PayabliTTPError.attestationFailed(reason: "unreadable")

        do {
            try await ttp.initialize()
            XCTFail("expected a failure")
        } catch let error as TapToPayError {
            XCTAssertEqual(error.type, .deviceKeyUnavailable)
        }

        XCTAssertEqual(ttp.sessionState, .failed(reason: .deviceKeyUnavailable))
    }

    /// The host read one id and its code was issued for it. A registration replaced since gets
    /// nothing sent, and the device is set up again.
    func testACodeForAReplacedRegistrationIsNotSent() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev_e"
        _ = try? await ttp.initialize()
        attestation.pendingRegistration = nil
        attestation.bindings = ["e": "dev_new"]

        do {
            try await ttp.activateDevice(activationCode: "123456")
            XCTFail("expected a failure")
        } catch let error as TapToPayError where error.type == .deviceSetupRequired {
        } catch {
            XCTFail("wrong error: \(error)")
        }

        XCTAssertEqual(ttp.sessionState, .failed(reason: .deviceSetupRequired))
    }

    /// Spending a code and building a session move the same state, so a build waits for an activation
    /// in progress rather than replacing the registration under it.
    func testAnInitializeWaitsForAnActivationInProgress() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.pendingRegistration = "dev_e"
        _ = try? await ttp.initialize()
        attestation.pendingRegistration = nil
        let gate = ActivationGate()
        attestation.beforeActivate = { await gate.hold() }

        let activation = Task { try await ttp.activateDevice(activationCode: "123456") }
        await gate.waitUntilHeld()
        let build = Task { try? await ttp.initialize() }
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        XCTAssertEqual(
            ttp.sessionState,
            .pendingActivation(activationId: "dev_e"),
            "initialize ran inside an activation"
        )

        await gate.release()
        try await activation.value
        _ = await build.value
        XCTAssertEqual(attestation.activateCalls, 1)
    }

    func testTheObjCReaderAnswersOnlyWhileActivationIsOwed() async throws {
        let (ttp, attestation) = try makeTTP()
        XCTAssertNil(ttp.activationId)

        attestation.pendingRegistration = "dev_e"
        _ = try? await ttp.initialize()

        XCTAssertEqual(ttp.activationId, "dev_e")

        try await ttp.activateDevice(activationCode: "ABC123")

        XCTAssertNil(ttp.activationId)
    }
}

/// Holds an activation open until a test releases it.
private actor ActivationGate {
    private var held = false
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false

    func hold() async {
        held = true
        heldWaiters.forEach { $0.resume() }
        heldWaiters = []
        guard !released else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilHeld() async {
        guard !held else { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
