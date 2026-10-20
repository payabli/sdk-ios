@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// An app the paypoint has not registered reaches a host as 3008 on every device route, and lands where
/// registering the app repairs it, whether or not the phone holds a registration.
@available(iOS 16.7, *)
@MainActor
final class AppRegistrationRefusalsTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    /// The refusals the service sends for an app it has not registered, in its own words.
    static let refusals: [(Int, String)] = [
        (403, "Application is not authorized for this paypoint."),
        (403, "No iOS apps are registered on the paypoint allowlist."),
        (400, "Assertion verification failed: Assertion rpIdHash does not match any app on the paypoint allowlist.")
    ]

    // MARK: - The classification

    func testEachRefusalIsDeviceSetupNotConfiguredWithTheServicesWordsInTheDetail() throws {
        for (status, reason) in Self.refusals {
            let error = try XCTUnwrap(AppRegistrationRefusals.hostError(status: status, reason: reason), reason)
            XCTAssertEqual(error.type, .deviceSetupNotConfigured, reason)
            XCTAssertEqual(error.reason, PayabliErrorType.deviceSetupNotConfigured.message, reason)
            XCTAssertEqual(error.detail, reason)
        }
    }

    func testOnlyTheWholeTextUnderItsOwnStatusMatches() {
        let cases: [(Int, String)] = [
            (400, "Assertion verification failed: signature mismatch"),
            (400, "Assertion verification failed: "),
            (400, "Assertion verification failed: Assertion rpIdHash does not match any app on the paypoint allowlist"),
            (400, "assertion verification failed: assertion rpIdHash does not match any app on the paypoint allowlist."),
            (403, "Assertion verification failed: Assertion rpIdHash does not match any app on the paypoint allowlist."),
            (400, "Application is not authorized for this paypoint."),
            (403, "Application is not authorized for this paypoint. "),
            (404, "No iOS apps are registered on the paypoint allowlist."),
            (403, "Entry point is not available for this request.")
        ]
        for (status, reason) in cases {
            XCTAssertNil(AppRegistrationRefusals.hostError(status: status, reason: reason), "\(status) \(reason)")
        }
    }

    // MARK: - /attest, a phone with nothing stored

    func testAnAttestRefusedForAnUnregisteredAppIs3008() async throws {
        StubURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            case "/api/v2/device/taptopay/attest":
                return Self.refusal(request, status: 403, reason: "Application is not authorized for this paypoint.")
            default:
                return AttestFixture.ok(request, ["deviceId": "dev_1"])
            }
        }
        let (sut, _, _) = try AttestFixture.makeService()

        do {
            _ = try await sut.attest(entry: "myEntry")
            XCTFail("a refused attestation reported success")
        } catch {
            XCTAssertEqual((error as? TapToPayError)?.type, .deviceSetupNotConfigured, "\(error)")
            XCTAssertEqual((error as? TapToPayError)?.detail, "Application is not authorized for this paypoint.")
        }
    }

    // MARK: - /activate, a phone holding a registration

    func testAnActivationRefusedForAnUnregisteredAppIs3008AndKeepsTheBinding() async throws {
        for (status, reason) in Self.refusals {
            let storage = InMemorySecureStorage()
            try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_1", keyId: "key_1", in: storage)
            StubURLProtocol.handler = { request in
                if request.url!.path == "/api/v2/device/taptopay/activate" {
                    return Self.refusal(request, status: status, reason: reason)
                }
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            }
            let (sut, _, _) = try AttestFixture.makeService(storage: storage)

            do {
                try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev_1")
                XCTFail("a refused activation reported success. \(reason)")
            } catch {
                XCTAssertEqual((error as? TapToPayError)?.type, .deviceSetupNotConfigured, "\(reason): \(error)")
            }
            XCTAssertEqual(try sut.binding(for: "myEntry")?.deviceId, "dev_1", reason)
        }
    }

    // MARK: - /config, a phone holding a registration

    func testAConfigurationRefusedForAnUnregisteredAppIs3008AndLandsOnConfigurationRejected() async throws {
        for (status, reason) in Self.refusals {
            let (ttp, attestation) = try makeTTP()
            attestation.cachedDeviceId = "dev_1"
            StubURLProtocol.handler = { request in Self.refusal(request, status: status, reason: reason) }

            do {
                try await ttp.initialize()
                XCTFail("initialize proceeded past \(reason)")
            } catch {
                XCTAssertEqual((error as? TapToPayError)?.type, .deviceSetupNotConfigured, "\(reason): \(error)")
                XCTAssertEqual((error as? TapToPayError)?.detail, reason)
            }
            XCTAssertEqual(ttp.sessionState, .failed(reason: .configurationRejected), reason)
            XCTAssertEqual(attestation.cachedDeviceId, "dev_1", "the registration is kept. \(reason)")
        }
    }

    /// Any other 403 still means the device owes an activation code.
    func testAnotherConfigurationRefusalStillLandsOnPendingActivation() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.cachedDeviceId = "dev_1"
        StubURLProtocol.handler = { request in Self.refusal(request, status: 403, reason: "Device is pending activation.") }

        _ = try? await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_1"))
    }

    // MARK: - Support

    private func makeTTP() throws -> (PayabliTTP, MockDeviceAttestationService) {
        let attestation = MockDeviceAttestationService()
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" })
        let ttp = PayabliTTP(
            config: config,
            provider: MockTapToPayProvider(),
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        return (ttp, attestation)
    }

    /// A refusal the way the service sends one: its result code as the HTTP status.
    private nonisolated static func refusal(
        _ request: URLRequest,
        status: Int,
        reason: String
    ) -> (HTTPURLResponse, Data) {
        let body: [String: Any] = [
            "isSuccess": false,
            "responseText": "Declined",
            "responseData": ["resultCode": status, "resultText": reason]
        ]
        return (
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!,
            try! JSONSerialization.data(withJSONObject: body)
        )
    }
}
