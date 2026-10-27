@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import Security
import XCTest

/// The catalog code each way of failing to set the device up reaches a caller with. The code decides
/// where the session lands, so a cause carried under the wrong one sends a host to a remedy that
/// cannot repair it.
final class AppAttestFailureCodeTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - App Attest refusing a key

    func testAKeyTheDeviceCannotMintIsReportedByWhatTheRefusalMeans() async throws {
        let cases: [(Error, PayabliErrorType)] = [
            (deviceCheck(1), .deviceSetupUnsupported),
            (deviceCheck(4), .deviceSetupUnavailable),
            (deviceCheck(0), .deviceSetupRequired),
            (deviceCheck(2), .deviceSetupRequired),
            (deviceCheck(3), .deviceSetupRequired),
            (NSError(domain: NSOSStatusErrorDomain, code: -1), .sdkInternalError)
        ]
        for (failure, expected) in cases {
            stubChallengeAndRegister()
            let (sut, attestor, _) = try AttestFixture.makeService()
            attestor.generateKeyError = failure

            await assertAttestThrows(sut, expected, "\(failure)")
        }
    }

    func testAKeyTheDeviceCannotAttestIsReportedByWhatTheRefusalMeans() async throws {
        let cases: [(Error, PayabliErrorType)] = [
            (deviceCheck(1), .deviceSetupUnsupported),
            (deviceCheck(4), .deviceSetupUnavailable),
            (deviceCheck(0), .deviceSetupRequired),
            (deviceCheck(2), .deviceSetupRequired),
            (deviceCheck(3), .deviceSetupRequired),
            (NSError(domain: NSOSStatusErrorDomain, code: -1), .sdkInternalError)
        ]
        for (failure, expected) in cases {
            stubChallengeAndRegister()
            let (sut, attestor, _) = try AttestFixture.makeService()
            attestor.attestKeyError = failure

            await assertAttestThrows(sut, expected, "\(failure)")
        }
    }

    /// App Attest answering with neither a value nor an error breaks its own contract, so retrying
    /// or setting up again cannot help.
    func testAnAnswerWithNeitherAValueNorAnErrorIsAnSDKDefect() {
        let result: Result<String, Error> = RealAppAttestor.completion(nil, nil, call: "generateKey")

        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual((error as? TapToPayError)?.type, .sdkInternalError, "\(error)")
        }
    }

    func testAnAnswerWithAnErrorIsPassedOnAsItArrived() {
        let result: Result<String, Error> = RealAppAttestor.completion("key", deviceCheck(4), call: "generateKey")

        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual((error as NSError).code, 4)
            XCTAssertEqual((error as NSError).domain, AppAttestService.deviceCheckErrorDomain)
        }
    }

    // MARK: - Secure storage

    /// The Keychain refuses every read and write before the first unlock after a boot, and answers
    /// once the phone is unlocked, so it is reported as storage that a retry can reach.
    func testAKeychainThatDoesNotAnswerAWriteIsSecureStorageUnavailable() throws {
        let storage = WriteRefusingStorage()
        let (sut, _, _) = try AttestFixture.makeService(storage: storage)
        try sut.remember(AttestedDevice(entry: "held", deviceId: "d0", keyId: "k0"))
        storage.refusesWrites = true

        XCTAssertThrowsError(try sut.remember(AttestedDevice(entry: "e", deviceId: "d", keyId: "k"))) { error in
            XCTAssertEqual((error as? TapToPayError)?.type, .deviceKeyUnavailable, "\(error)")
        }
        storage.refusesWrites = false
        XCTAssertEqual(try sut.binding(for: "held")?.deviceId, "d0", "the refused write changed the store")
        XCTAssertNil(try sut.binding(for: "e"), "the refused write was kept")
    }

    /// A Keychain status is reported by what repairs it: a missing entitlement is the app's
    /// configuration, an invalid parameter is this SDK's own query, and the rest is storage that did
    /// not answer.
    func testAKeychainStatusIsReportedByWhatRepairsIt() throws {
        let cases: [(OSStatus, PayabliErrorType)] = [
            (errSecInteractionNotAllowed, .deviceKeyUnavailable),
            (errSecMissingEntitlement, .deviceSetupNotConfigured),
            (errSecParam, .sdkInternalError)
        ]
        for (status, expected) in cases {
            let storage = InMemorySecureStorage()
            storage.readFailure = KeychainStorage.KeychainError.underlying(status)
            let (sut, _, _) = try AttestFixture.makeService(storage: storage)

            XCTAssertThrowsError(try sut.binding(for: "myEntry")) { error in
                XCTAssertEqual((error as? TapToPayError)?.type, expected, "status \(status): \(error)")
            }
        }
    }

    // MARK: - The assertion that signs an activation

    /// An activation whose assertion cannot be produced does not send `/activate`, and reports the
    /// failure by what repairs it.
    func testAnActivationThatCannotBeSignedIsNotSentAndIsReportedByItsCause() async throws {
        let cases: [(Error, PayabliErrorType)] = [
            (deviceCheck(1), .deviceSetupUnsupported),
            (deviceCheck(4), .deviceSetupUnavailable),
            (deviceCheck(2), .deviceSetupRequired),
            (deviceCheck(3), .deviceSetupRequired),
            (deviceCheck(0), .sdkInternalError),
            (NSError(domain: NSOSStatusErrorDomain, code: -1), .sdkInternalError)
        ]
        for (failure, expected) in cases {
            let paths = PathsBox()
            StubURLProtocol.handler = { request in
                paths.append(request.url!.path)
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            }
            let storage = InMemorySecureStorage()
            try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
            let (sut, attestor, _) = try AttestFixture.makeService(storage: storage)
            attestor.generateAssertionError = failure

            do {
                try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev")
                XCTFail("the activation was sent unsigned. \(failure)")
            } catch let signing as ActivationSigningFailed {
                XCTAssertEqual(signing.hostError.type, expected, "\(failure)")
            } catch {
                XCTFail("\(failure) reached the caller as \(error)")
            }
            XCTAssertFalse(paths.values.contains("/api/v2/device/taptopay/activate"), "\(failure): \(paths.values)")
        }
    }

    /// A store failure the Keychain did not report is this SDK's own.
    func testAStoreFailureTheKeychainDidNotReportIsAnSDKDefect() throws {
        let (sut, _, _) = try AttestFixture.makeService(storage: UnreadableStorage())

        XCTAssertThrowsError(try sut.remember(AttestedDevice(entry: "e", deviceId: "d", keyId: "k"))) { error in
            XCTAssertEqual((error as? TapToPayError)?.type, .sdkInternalError, "\(error)")
        }
    }

    // MARK: - A response that cannot be read

    func testAChallengeResponseThatCannotBeDecodedIsADecodingError() async throws {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                Data("not json".utf8)
            )
        }
        let (sut, _, _) = try AttestFixture.makeService()

        await assertAttestThrows(sut, .decodingError)
    }

    func testAChallengeResponseWithNoPayloadIsADecodingError() async throws {
        StubURLProtocol.handler = { request in
            let body = try! JSONSerialization.data(withJSONObject: [
                "responseCode": 1,
                "isSuccess": true,
                "responseText": "OK"
            ])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                body
            )
        }
        let (sut, _, _) = try AttestFixture.makeService()

        await assertAttestThrows(sut, .decodingError)
    }

    func testARegistrationResponseThatCannotBeReadIsADecodingError() async throws {
        let bodies: [Data] = [
            Data("not json".utf8),
            AttestFixture.envelope(responseData: ["status": "active"])
        ]
        for body in bodies {
            StubURLProtocol.handler = { request in
                if request.url!.path == "/api/v2/device/taptopay/challenge" {
                    return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
                }
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    body
                )
            }
            let (sut, _, _) = try AttestFixture.makeService()

            await assertAttestThrows(sut, .decodingError, String(bytes: body, encoding: .utf8) ?? "")
        }
    }

    // MARK: - A device that cannot be identified

    /// With no bundle identifier there is no install identity, and `/register` answers a blank one
    /// with a refusal, so nothing is sent.
    func testAnInstallWithNoIdentityIsRefusedBeforeRegistering() async throws {
        let paths = PathsBox()
        StubURLProtocol.handler = { request in
            paths.append(request.url!.path)
            if request.url!.path == "/api/v2/device/taptopay/challenge" {
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            }
            return AttestFixture.ok(request, ["deviceId": "dev_1"])
        }
        let (sut, _, _) = try AttestFixture.makeService(hardwareIdProvider: { "" })

        await assertAttestThrows(sut, .deviceIdentityUnavailable)
        XCTAssertFalse(paths.values.contains("/api/v2/device/taptopay/register"), "\(paths.values)")
    }

    // MARK: - A cold route's refusal names its own cause

    /// Every cold route refuses a closed entry point with the same words, and the
    /// words — not the status alone — decide the answer a host gets.
    func testAnEntryPointRefusalOnEveryColdRouteReportsItsOwnCode() async throws {
        let routes = [
            "/api/v2/device/taptopay/register",
            "/api/v2/device/taptopay/challenge",
            "/api/v2/device/taptopay/attest"
        ]
        for route in routes {
            stubColdRoutes(refusing: route, status: 403, text: "Entry point is not available for this request.")
            let (sut, _, _) = try AttestFixture.makeService()

            await assertAttestThrows(sut, .entryPointRefused, route)
        }
    }

    /// A 400 whose words say the attestation did not verify is a refusal of this
    /// device's setup, not a malformed request.
    func testAnAttestationThatFailedVerificationReportsSetupRefused() async throws {
        stubColdRoutes(
            refusing: "/api/v2/device/taptopay/attest",
            status: 400,
            text: "Attestation verification failed: nonce mismatch"
        )
        let (sut, _, _) = try AttestFixture.makeService()

        await assertAttestThrows(sut, .deviceSetupRefused)
    }

    /// The root-unavailable sentence is ruled to keep the validation answer, so the
    /// verification match above must be the whole sentence, not a prefix.
    func testAnAttestationRootUnavailableFailureKeepsTheValidationError() async throws {
        stubColdRoutes(
            refusing: "/api/v2/device/taptopay/attest",
            status: 400,
            text: "Attestation verification failed: Apple attestation root is unavailable."
        )
        let (sut, _, _) = try AttestFixture.makeService()

        await assertAttestThrows(sut, .validation)
    }

    /// A device the service no longer holds is set up again, whichever words told
    /// the route so.
    func testADeviceTheServiceNoLongerHoldsReportsSetupRequired() async throws {
        let cases: [(String, Int, String)] = [
            ("/api/v2/device/taptopay/attest", 404, "Device not found."),
            ("/api/v2/device/taptopay/attest", 403, "Device is not in a state that allows this operation.")
        ]
        for (route, status, text) in cases {
            stubColdRoutes(refusing: route, status: status, text: text)
            let (sut, _, _) = try AttestFixture.makeService()

            await assertAttestThrows(sut, .deviceSetupRequired, text)
        }
    }

    /// A refusal none of the tables knows keeps the status's own answer.
    func testAnUnmatchedRefusalKeepsItsStatusAnswer() async throws {
        stubColdRoutes(refusing: "/api/v2/device/taptopay/attest", status: 403, text: "Some other refusal.")
        let (sut, _, _) = try AttestFixture.makeService()

        await assertAttestThrows(sut, .permissionDenied)
    }

    // MARK: - The activation code itself

    /// A code that is not six digits is refused before anything is sent, and the
    /// session still waits for a valid one.
    @available(iOS 16.7, *)
    @MainActor
    func testAnActivationCodeThatIsNotSixDigitsIsRefusedBeforeTheServiceSeesIt() async throws {
        for code in ["12345", "1234567", "12345a", "abcdef", ""] {
            let (ttp, attestation) = try await makePendingActivationTTP()

            do {
                try await ttp.activateDevice(activationCode: code)
                XCTFail("\(code): the attempt proceeded")
            } catch {
                let host = TapToPayErrorTranslation.hostError(for: error)
                XCTAssertEqual((host as? TapToPayError)?.type, .activationCodeMalformed, "\(code): \(error)")
            }
            XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_1"), "\(code)")
            XCTAssertEqual(attestation.activateCalls, 0, "\(code)")
        }
    }

    /// Activating with nothing stored names the missing setup as its own cause:
    /// the remedy is to run the setup again, not an unknown failure.
    func testActivatingWithNothingStoredReportsSetupRequired() async throws {
        let (sut, _, _) = try AttestFixture.makeService()

        do {
            try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev_1")
            XCTFail("activation succeeded with nothing stored")
        } catch {
            let host = TapToPayErrorTranslation.hostError(for: error)
            XCTAssertEqual((host as? TapToPayError)?.type, .deviceSetupRequired, "\(error)")
        }
    }

    // MARK: - Helpers

    private func deviceCheck(_ code: Int) -> NSError {
        NSError(domain: AppAttestService.deviceCheckErrorDomain, code: code)
    }

    private func stubChallengeAndRegister() {
        StubURLProtocol.handler = { request in
            if request.url!.path == "/api/v2/device/taptopay/challenge" {
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            }
            return AttestFixture.ok(request, ["deviceId": "dev_1"])
        }
    }

    /// Answers the cold routes: the refused one with its status and words, `/challenge`
    /// with its fixture, and every other route with a device id.
    private func stubColdRoutes(refusing refusedPath: String, status: Int, text: String) {
        StubURLProtocol.handler = { request in
            let path = request.url!.path
            if path == refusedPath {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.refusalBody(status: status, text: text)
                )
            }
            if path == "/api/v2/device/taptopay/challenge" {
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            }
            return AttestFixture.ok(request, ["deviceId": "dev_1"])
        }
    }

    /// A legacy-envelope refusal, the shape every device route answers one in: the
    /// status as the result code, the service's words as the result text.
    private static func refusalBody(status: Int, text: String) -> Data {
        let payload: [String: Any] = [
            "isSuccess": false,
            "responseData": ["resultCode": status, "resultText": text]
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    private func assertAttestThrows(
        _ sut: AppAttestService,
        _ type: PayabliErrorType,
        _ message: String = "",
        line: UInt = #line
    ) async {
        do {
            _ = try await sut.attest(entry: "myEntry")
            XCTFail("the attempt proceeded. \(message)", line: line)
        } catch {
            let host = TapToPayErrorTranslation.hostError(for: error)
            XCTAssertEqual((host as? TapToPayError)?.type, type, "\(error) \(message)", line: line)
        }
    }

    /// A facade waiting for an activation code, the state `activateDevice` runs from.
    @available(iOS 16.7, *)
    @MainActor
    private func makePendingActivationTTP() async throws -> (PayabliTTP, MockDeviceAttestationService) {
        let config = try PayabliConfig(entryPoint: "myEntry", environment: .sandbox, tokenProvider: { "seed" })
        let attestation = MockDeviceAttestationService()
        attestation.pendingRegistration = "dev_1"
        let ttp = PayabliTTP(
            config: config,
            provider: MockTapToPayProvider(),
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        _ = try? await ttp.initialize()
        XCTAssertEqual(
            ttp.sessionState,
            .pendingActivation(activationId: "dev_1"),
            "the fixture itself is broken if this fails"
        )
        return (ttp, attestation)
    }
}

/// A store whose reads fail with an error the Keychain did not raise.
private struct UnreadableStorage: SecureStorage {
    struct Unreadable: Error {}

    func string(forKey _: String) throws -> String? {
        throw Unreadable()
    }

    func set(_: String, forKey _: String) throws {
        throw Unreadable()
    }

    func remove(forKey _: String) throws {
        throw Unreadable()
    }
}
