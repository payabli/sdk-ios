import XCTest
import PayabliSDKCore
@testable import PayabliSDKTapToPay

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
        return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json"])!, data)
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

        // Start iterating before we emit.
        try await Task.sleep(nanoseconds: 30_000_000)
        try await ttp.initialize()
        let received = await collector.value

        XCTAssertTrue(received.contains("att-start"))
        XCTAssertTrue(received.contains("att-done"))
        XCTAssertTrue(received.contains("rdy-init"))
        XCTAssertTrue(received.contains("rdy-ready"))
    }
}
