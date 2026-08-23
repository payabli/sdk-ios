@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

final class AppAttestServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeAttest(
        storage: SecureStorage = InMemorySecureStorage()
    ) -> (AppAttestService, MockAppAttestor, PayabliAuth) {
        let urlSession = StubURLProtocol.makeSession()
        let service = PayabliService(environment: .sandbox, session: urlSession)
        let config = PayabliConfig(
            accessToken: "seed",
            entryPoint: "myEntry",
            environment: .sandbox
        )
        let auth = PayabliAuth(config: config)
        let transport = AuthenticatedTransport(base: service, auth: auth)
        let attestor = MockAppAttestor()
        let sut = AppAttestService(
            transport: transport,
            attestor: attestor,
            storage: storage,
            hardwareIdProvider: { "fixed-hw-id" },
            deviceNameProvider: { "iPhone" },
            modelProvider: { "iPhone15,2" },
            osVersionProvider: { "17.0" }
        )
        return (sut, attestor, auth)
    }

    /// Writes a binding the way the service does, so a test starts warm.
    private func seedBinding(
        entry: String,
        deviceId: String,
        keyId: String,
        in storage: SecureStorage
    ) throws {
        let bindings = DeviceBindings([AttestedDevice(entry: entry, deviceId: deviceId, keyId: keyId)])
        let data = try JSONEncoder().encode(bindings)
        try storage.set(XCTUnwrap(String(bytes: data, encoding: .utf8)), forKey: PayabliKeychainKey.deviceBindings)
    }

    /// `XCTAssertTrue` takes an autoclosure, which cannot await, so the answer is
    /// read first and asserted second.
    private func assertAttested(
        _ sut: AppAttestService,
        _ entry: String,
        _ expected: Bool,
        _ message: String = "",
        line: UInt = #line
    ) async {
        let actual = await sut.isAttested(for: entry)
        XCTAssertEqual(actual, expected, message, line: line)
    }

    private func response(_ status: Int, body: Data, url: URL) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!, body)
    }

    private static func envelope(responseData: [String: Any]) -> Data {
        let payload: [String: Any] = [
            "responseCode": 1,
            "isSuccess": true,
            "responseText": "OK",
            "responseData": responseData
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - First-run flow

    func testFirstRunAttestHitsAllThreeEndpoints() async throws {
        let pathsBox = PathsBox()
        StubURLProtocol.handler = { request in
            pathsBox.append(request.url!.path)
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
                )
            case "/api/v2/device/taptopay/register":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["deviceId": "dev_1"])
                )
            case "/api/v2/device/taptopay/attest":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["ok": true])
                )
            default:
                XCTFail("unexpected path: \(request.url!.path)")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
        }

        let storage = InMemorySecureStorage()
        let (sut, attestor, _) = makeAttest(storage: storage)

        await assertAttested(sut, "myEntry", false)
        let result = try await sut.attest(entry: "myEntry", appId: "TEAM.bundle.id")

        XCTAssertEqual(result.deviceId, "dev_1")
        XCTAssertEqual(result.keyId, "mock_keyId")
        XCTAssertEqual(attestor.generateKeyCalls, 1)
        XCTAssertEqual(attestor.attestKeyCalls, 1)
        XCTAssertEqual(pathsBox.values, [
            "/api/v2/device/taptopay/challenge",
            "/api/v2/device/taptopay/register",
            "/api/v2/device/taptopay/attest"
        ])

        // Persistence
        await assertAttested(sut, "myEntry", true)
        XCTAssertEqual(sut.binding(for: "myEntry")?.keyId, "mock_keyId")
        XCTAssertEqual(sut.binding(for: "myEntry")?.deviceId, "dev_1")
    }

    // MARK: - Pending activation

    func testPendingStatusCompletesAttestationThenThrowsActivationError() async throws {
        let pathsBox = PathsBox()
        StubURLProtocol.handler = { request in
            pathsBox.append(request.url!.path)
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["challengeId": "c", "challenge": "Y2hhbGxlbmdl"])
                )
            case "/api/v2/device/taptopay/register":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["deviceId": "dev_pending", "status": "pending"])
                )
            case "/api/v2/device/taptopay/attest":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["ok": true])
                )
            default:
                XCTFail("unexpected path: \(request.url!.path)")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
        }

        let storage = InMemorySecureStorage()
        let (sut, attestor, _) = makeAttest(storage: storage)
        do {
            _ = try await sut.attest(entry: "myEntry", appId: "x")
            XCTFail("expected throw")
        } catch PayabliTTPError.devicePendingActivation {
            // Pending must still surface, BUT only after the full attestation
            // (including /attest) has completed so that /activate can later
            // verify the Apple assertion and find the DeviceAttestations row.
            XCTAssertEqual(pathsBox.values, [
                "/api/v2/device/taptopay/challenge",
                "/api/v2/device/taptopay/register",
                "/api/v2/device/taptopay/attest"
            ])
            XCTAssertEqual(attestor.generateKeyCalls, 1)
            XCTAssertEqual(attestor.attestKeyCalls, 1)
            XCTAssertEqual(sut.binding(for: "myEntry")?.deviceId, "dev_pending")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Transactional persistence

    /// A failure partway through attestation (here: `attestKey`) must NOT leave
    /// a keyId/deviceId in the Keychain. Otherwise `isAlreadyAttested` would
    /// report `true`, the warm path would skip re-attestation, and
    /// `generateAssertion` would fail forever on a never-attested key.
    func testAttestDoesNotPersistIdentityWhenAttestationFails() async throws {
        StubURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
                )
            case "/api/v2/device/taptopay/register":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["deviceId": "dev_1"])
                )
            default:
                XCTFail("attest must not reach \(request.url!.path) once attestKey fails")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
        }

        let storage = InMemorySecureStorage()
        let (sut, attestor, _) = makeAttest(storage: storage)
        attestor.attestKeyError = NSError(domain: AppAttestService.deviceCheckErrorDomain, code: 2)

        do {
            _ = try await sut.attest(entry: "myEntry", appId: "x")
            XCTFail("expected throw")
        } catch {
            // expected
        }

        await assertAttested(sut, "myEntry", false)
        XCTAssertNil(sut.binding(for: "myEntry")?.keyId)
        XCTAssertNil(sut.binding(for: "myEntry")?.deviceId)
        // `attestKey` burns the key, so the pending slot must be cleared too:
        // the next attempt must mint a new key rather than replay a burned one.
        XCTAssertNil(storage.string(forKey: PayabliKeychainKey.pendingKeyId))
    }

    /// A failure BEFORE `attestKey` (here: `/register`) must keep the freshly
    /// generated key in the pending slot so the retry reuses it instead of
    /// minting a new Secure Enclave key on every attempt.
    func testAttestReusesPendingKeyAcrossPreAttestFailures() async throws {
        let registerAttempts = CountBox()
        StubURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
                )
            case "/api/v2/device/taptopay/register":
                // Fail the first /register (pre-attest); succeed the second.
                if registerAttempts.increment() == 1 {
                    return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1", headerFields: nil)!, Data())
                }
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["deviceId": "dev_1"])
                )
            case "/api/v2/device/taptopay/attest":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["ok": true])
                )
            default:
                XCTFail("unexpected path: \(request.url!.path)")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
        }

        let storage = InMemorySecureStorage()
        let (sut, attestor, _) = makeAttest(storage: storage)

        // Attempt 1 fails at /register (after the key was generated + cached).
        do {
            _ = try await sut.attest(entry: "myEntry", appId: "x")
            XCTFail("expected first attempt to throw")
        } catch {
            // expected
        }
        XCTAssertEqual(attestor.generateKeyCalls, 1)
        await assertAttested(sut, "myEntry", false)
        XCTAssertEqual(
            sut.pendingKey(for: "myEntry"),
            "mock_keyId",
            "a pre-attest failure must keep the generated key for reuse"
        )

        // Attempt 2 succeeds and must REUSE the pending key — no new generateKey.
        let result = try await sut.attest(entry: "myEntry", appId: "x")
        XCTAssertEqual(result.keyId, "mock_keyId")
        XCTAssertEqual(attestor.generateKeyCalls, 1, "the pending key should be reused, not regenerated")
        XCTAssertEqual(attestor.attestKeyCalls, 1)
        await assertAttested(sut, "myEntry", true)
        XCTAssertNil(
            storage.string(forKey: PayabliKeychainKey.pendingKeyId),
            "pending slot must be cleared once attestation completes"
        )
    }

    // MARK: - The key an attestation is part way through

    /// A key can be attested once, so two paypoints must not share one, and
    /// starting one must not take the other's away.
    func testAPendingKeyIsReusedOnlyByTheEntryPointThatMintedIt() throws {
        let (sut, _, _) = makeAttest()
        try sut.rememberPendingKey("key_for_a", for: "entryA")
        try sut.rememberPendingKey("key_for_b", for: "entryB")

        XCTAssertEqual(sut.pendingKey(for: "entryB"), "key_for_b")

        XCTAssertEqual(sut.pendingKey(for: "entryA"), "key_for_a", "one entry point's key was overwritten")
        XCTAssertNil(sut.pendingKey(for: "entryC"), "an entry point that minted nothing must read nothing")
    }

    /// A retry inside one entry point still reuses its own key rather than minting
    /// another on every attempt.
    func testTheSameEntryPointReusesItsPendingKey() async throws {
        let storage = InMemorySecureStorage()
        let (sut, attestor, _) = makeAttest(storage: storage)
        try sut.rememberPendingKey("already_minted", for: "myEntry")

        StubURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
                )
            case "/api/v2/device/taptopay/register":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["deviceId": "dev_1"])
                )
            default:
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Self.envelope(responseData: ["ok": true])
                )
            }
        }

        let result = try await sut.attest(entry: "myEntry", appId: "TEAM.bundle.id")

        XCTAssertEqual(result.keyId, "already_minted")
        XCTAssertEqual(attestor.generateKeyCalls, 0, "a retry minted a second key")
    }

    /// Clearing one paypoint must leave another's retry alone: taking it away
    /// makes the next attempt mint a key and register another device.
    func testClearingOnePaypointKeepsAnothersPendingKey() throws {
        let (sut, _, _) = makeAttest()
        try sut.rememberPendingKey("key_for_a", for: "entryA")
        try sut.rememberPendingKey("key_for_b", for: "entryB")

        sut.clearCache(for: "entryA")

        XCTAssertNil(sut.pendingKey(for: "entryA"))
        XCTAssertEqual(sut.pendingKey(for: "entryB"), "key_for_b")
    }

    // MARK: - Retention

    /// Reading is what makes a binding recent. Ordering by enrolment instead
    /// evicts the binding every session uses in favour of one that enrolled later.
    func testUsingABindingMovesItToTheFront() throws {
        let (sut, _, _) = makeAttest()
        for name in ["a", "b", "c", "d"] {
            try sut.remember(AttestedDevice(entry: name, deviceId: "dev-\(name)", keyId: "key-\(name)"))
        }

        // "a" is the coldest by enrolment, and using it makes it the newest.
        XCTAssertNotNil(sut.binding(for: "a"))
        try sut.remember(AttestedDevice(entry: "e", deviceId: "dev-e", keyId: "key-e"))

        XCTAssertNotNil(sut.binding(for: "a"), "the binding just used was the one evicted")
        XCTAssertNil(sut.binding(for: "b"), "the coldest binding should have gone")
    }

    /// Four, so a device moved between paypoints finds each where it left it.
    func testOnlyFourBindingsAreKept() throws {
        let (sut, _, _) = makeAttest()

        for index in 0 ..< 6 {
            try sut.remember(AttestedDevice(entry: "e\(index)", deviceId: "d\(index)", keyId: "k\(index)"))
        }

        XCTAssertEqual(sut.allBindings().bindings.count, DeviceBindings.maximum)
        XCTAssertNil(sut.binding(for: "e0"))
        XCTAssertNotNil(sut.binding(for: "e5"))
    }

    /// A write that fails has to be raised. Nothing keeps an in-memory copy, so
    /// reporting the enrolment as done leaves the service holding a device this
    /// one cannot name: the next request fails for a missing binding, and a device
    /// awaiting activation cannot activate at all.
    func testAWriteThatFailsIsRaised() {
        let (sut, _, _) = makeAttest(storage: FailingStorage())

        XCTAssertThrowsError(
            try sut.remember(AttestedDevice(entry: "e", deviceId: "d", keyId: "k"))
        )
    }

    // MARK: - Whether the key is still there

    /// The check the sibling SDK makes by comparing thumbprints. App Attest hands
    /// back an opaque identifier, so the key is asked instead: a platform that
    /// will not sign with it says the binding names a key this device no longer
    /// holds, whatever the reason.
    func testABindingWhoseKeyIsGoneIsNotAnEnrolment() async throws {
        // 2 is what a key that no longer exists reports, measured on a device
        // after a reinstall; 3 is the code the platform documents for a key it
        // rejects. Both mean this binding cannot produce an assertion.
        for code in [2, 3] {
            let storage = InMemorySecureStorage()
            try seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
            let (sut, attestor, _) = makeAttest(storage: storage)
            attestor.generateAssertionError = NSError(
                domain: AppAttestService.deviceCheckErrorDomain,
                code: code
            )

            await assertAttested(sut, "myEntry", false, "code \(code)")

            XCTAssertNil(
                sut.binding(for: "myEntry"),
                "a binding naming a key that is gone has to be dropped, not asked again every start"
            )
        }
    }

    /// Every other failure is this device having a bad moment. Re-enrolling on one
    /// costs an enrolment for a key that was working.
    func testABindingSurvivesAKeyCheckThatCouldNotBeMade() async throws {
        for code in [0, 1, 4] {
            let storage = InMemorySecureStorage()
            try seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
            let (sut, attestor, _) = makeAttest(storage: storage)
            attestor.generateAssertionError = NSError(
                domain: AppAttestService.deviceCheckErrorDomain,
                code: code
            )

            await assertAttested(sut, "myEntry", true, "code \(code) is not a reason to re-enrol")
            XCTAssertNotNil(sut.binding(for: "myEntry"), "code \(code)")
        }
    }

    /// A key that signs is a key this device holds.
    func testABindingWhoseKeySignsIsAnEnrolment() async throws {
        let storage = InMemorySecureStorage()
        try seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
        let (sut, _, _) = makeAttest(storage: storage)

        await assertAttested(sut, "myEntry", true)
        XCTAssertEqual(sut.cachedDeviceId(for: "myEntry"), "dev")
    }

    /// Asking about a paypoint with no binding asks the platform nothing: there is
    /// no key to ask about, and a signature attempt would be wasted.
    func testNoBindingAsksThePlatformNothing() async {
        let (sut, attestor, _) = makeAttest()

        await assertAttested(sut, "myEntry", false)

        XCTAssertEqual(attestor.generateAssertionCalls, 0)
    }

    // MARK: - Assertion generation

    func testGenerateAssertionProducesHeaders() async throws {
        let storage = InMemorySecureStorage()
        try seedBinding(entry: "myEntry", deviceId: "cached_deviceId", keyId: "cached_keyId", in: storage)

        let (sut, attestor, _) = makeAttest(storage: storage)
        let headers = try await sut.generateAssertion(for: "myEntry")
        XCTAssertEqual(headers.keyId, "cached_keyId")
        XCTAssertEqual(headers.deviceId, "cached_deviceId")
        XCTAssertFalse(headers.assertion.isEmpty)
        XCTAssertFalse(headers.timestamp.isEmpty)
        XCTAssertEqual(attestor.generateAssertionCalls, 1)
    }

    func testGenerateAssertionFailsWithoutState() async throws {
        let (sut, _, _) = makeAttest()
        do {
            _ = try await sut.generateAssertion(for: "myEntry")
            XCTFail("expected throw")
        } catch PayabliTTPError.attestationFailed {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// A DeviceCheck failure from `generateAssertion` means the cached key is
    /// unusable (never attested, or the App Attest environment changed). The
    /// service must clear the cache so the next `initialize()` re-attests.
    func testGenerateAssertionClearsTheBindingOnAnInvalidKey() async throws {
        let storage = InMemorySecureStorage()
        try seedBinding(entry: "myEntry", deviceId: "cached_deviceId", keyId: "cached_keyId", in: storage)

        let (sut, attestor, _) = makeAttest(storage: storage)
        attestor.generateAssertionError = NSError(
            domain: AppAttestService.deviceCheckErrorDomain,
            code: 3
        )

        do {
            _ = try await sut.generateAssertion(for: "myEntry")
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual((error as NSError).domain, AppAttestService.deviceCheckErrorDomain)
        }

        await assertAttested(sut, "myEntry", false, "a rejected key has to be re-attested")
    }

    /// Every other DeviceCheck error keeps the binding. `DCErrorServerUnavailable`
    /// asks for a retry with the same key, which preserves the device's risk
    /// metric, so clearing throws away a key that was working.
    func testGenerateAssertionKeepsTheBindingOnEveryOtherDeviceCheckError() async throws {
        for code in [0, 1, 4] {
            let storage = InMemorySecureStorage()
            try seedBinding(entry: "myEntry", deviceId: "cached_deviceId", keyId: "cached_keyId", in: storage)
            let (sut, attestor, _) = makeAttest(storage: storage)
            attestor.generateAssertionError = NSError(
                domain: AppAttestService.deviceCheckErrorDomain,
                code: code
            )

            do {
                _ = try await sut.generateAssertion(for: "myEntry")
                XCTFail("expected throw for code \(code)")
            } catch {
                XCTAssertEqual((error as NSError).code, code)
            }

            await assertAttested(sut, "myEntry", true, "code \(code) is not a reason to re-attest")
        }
    }

    /// A non-DeviceCheck failure (e.g. a transient wrapper error) must NOT wipe
    /// a perfectly valid attestation.
    func testGenerateAssertionKeepsCacheOnNonDeviceCheckError() async throws {
        let storage = InMemorySecureStorage()
        try seedBinding(entry: "myEntry", deviceId: "cached_deviceId", keyId: "cached_keyId", in: storage)

        let (sut, attestor, _) = makeAttest(storage: storage)
        attestor.generateAssertionError = NSError(domain: "com.example.other", code: 7)

        do {
            _ = try await sut.generateAssertion(for: "myEntry")
            XCTFail("expected throw")
        } catch {
            // expected
        }

        await assertAttested(sut, "myEntry", true, "non-DeviceCheck failures must not clear attestation state")
    }

    // MARK: - clearCache

    func testClearCacheRemovesThisEntryPointsBinding() async throws {
        let storage = InMemorySecureStorage()
        try seedBinding(entry: "myEntry", deviceId: "b", keyId: "a", in: storage)
        let (sut, _, _) = makeAttest(storage: storage)

        sut.clearCache(for: "myEntry")

        await assertAttested(sut, "myEntry", false)
    }

    /// A refusal is about the paypoint that refused. The other bindings still
    /// name keys that work, and each one dropped costs an enrolment.
    func testClearCacheLeavesEveryOtherBindingAlone() async throws {
        let storage = InMemorySecureStorage()
        let (sut, _, _) = makeAttest(storage: storage)
        try sut.remember(AttestedDevice(entry: "entryA", deviceId: "devA", keyId: "keyA"))
        try sut.remember(AttestedDevice(entry: "entryB", deviceId: "devB", keyId: "keyB"))

        sut.clearCache(for: "entryA")

        await assertAttested(sut, "entryA", false)
        XCTAssertEqual(sut.cachedDeviceId(for: "entryB"), "devB")
    }

    /// The defect this ticket names: a session configured for one paypoint while
    /// holding another's handle must report not enrolled, so nothing is sent and
    /// the other paypoint's record is left intact.
    func testAHandleFromAnotherPaypointIsNotThisOnesEnrolment() async throws {
        let storage = InMemorySecureStorage()
        let (sut, _, _) = makeAttest(storage: storage)
        try sut.remember(AttestedDevice(entry: "entryA", deviceId: "devA", keyId: "keyA"))

        await assertAttested(sut, "entryB", false)
        XCTAssertNil(sut.cachedDeviceId(for: "entryB"))
        XCTAssertEqual(sut.cachedDeviceId(for: "entryA"), "devA")
    }

    /// An identity stored before the paypoint was recorded cannot be adopted:
    /// nothing says which paypoint issued it, and presenting it to the wrong one
    /// is what retires a device that was still active. It goes, and the device
    /// enrols once.
    func testAnIdentityStoredWithoutItsPaypointIsDiscarded() async throws {
        let storage = InMemorySecureStorage()
        try storage.set("old_key", forKey: "com.payabli.ttp.keyId")
        try storage.set("old_device", forKey: "com.payabli.ttp.deviceId")

        let (sut, _, _) = makeAttest(storage: storage)

        await assertAttested(sut, "myEntry", false)
        XCTAssertNil(storage.string(forKey: "com.payabli.ttp.keyId"))
        XCTAssertNil(storage.string(forKey: "com.payabli.ttp.deviceId"))
    }
}

/// Thread-safe box so the stub handler can record the order of paths it sees.
/// A store whose writes always fail, for the one case that has to be raised.
private struct FailingStorage: SecureStorage {
    func string(forKey _: String) -> String? {
        nil
    }

    func set(_: String, forKey _: String) throws {
        throw KeychainStorage.KeychainError.decoding
    }

    func remove(forKey _: String) {}
}

private final class PathsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ s: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(s)
    }
}

/// Thread-safe monotonic counter so a stub handler can vary its response by
/// call ordinal (e.g. fail the first request, succeed the next).
private final class CountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    /// Increments and returns the new value (first call returns 1).
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}
