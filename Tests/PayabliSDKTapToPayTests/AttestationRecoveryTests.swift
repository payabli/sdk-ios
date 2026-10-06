@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// What a start does with the binding it finds: one it cannot use is enrolled over
/// under the same install, and one it can use is left alone.
final class AttestationRecoveryTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private static let bundleIdentifier = "com.acme.checkout"

    /// Records every register body and answers the rest of the cold sequence.
    private func stubColdSequence(registers: BodyBox) {
        StubURLProtocol.handler = { request in
            if request.url!.path == "/api/v2/device/taptopay/register" {
                registers.append(request.payabliTestBody)
                return AttestFixture.ok(request, ["deviceId": "dev_1"])
            }
            if request.url!.path == "/api/v2/device/taptopay/challenge" {
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            }
            return AttestFixture.ok(request, ["ok": true])
        }
    }

    private func sentHardwareId(_ body: Data?) throws -> String {
        let sent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
        )
        return try XCTUnwrap(sent["hardwareId"] as? String)
    }

    /// A stored binding that will not decode is the same answer on every read, so it
    /// is treated as absent and enrolled over. The install is unchanged, so the
    /// service is sent the identifier it already holds a row for.
    func testABindingThatWillNotDecodeIsEnrolledOverUnderTheSameInstall() async throws {
        let storage = InMemorySecureStorage()
        let before = try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: Self.bundleIdentifier)
        try storage.set("{ not json", forKey: PayabliKeychainKey.deviceBindings)
        let registers = BodyBox()
        stubColdSequence(registers: registers)
        let (sut, _, _) = try AttestFixture.makeService(
            storage: storage,
            hardwareIdProvider: {
                try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: Self.bundleIdentifier)
            }
        )

        let attested = try await sut.isAttested(for: "myEntry")
        XCTAssertFalse(attested)
        _ = try await sut.attest(entry: "myEntry")

        XCTAssertEqual(registers.values.count, 1)
        XCTAssertEqual(try sentHardwareId(registers.values.first ?? nil), before)
        XCTAssertEqual(try sut.cachedDeviceId(for: "myEntry"), "dev_1")
    }

    /// A start that finds a binding whose key signs registers nothing, so the
    /// service has nothing to change about the device, however often it runs.
    @MainActor
    func testABindingThatWorksIsLeftAloneOnEveryStart() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "e", deviceId: "dev_seed", keyId: "key", in: storage)
        let registers = BodyBox()
        StubURLProtocol.handler = { request in
            if request.url!.path == "/api/v2/device/taptopay/register" {
                registers.append(request.payabliTestBody)
                return AttestFixture.ok(request, ["deviceId": "dev_registered_again"])
            }
            if request.url!.path == "/api/v2/device/taptopay/challenge" {
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            }
            return AttestFixture.ok(request, [
                "credentials": ["secretKey": "s", "apiKey": "a", "merchantId": "m", "terminalId": "t"]
            ])
        }
        let (attestation, _, _) = try AttestFixture.makeService(storage: storage)
        let ttp = try PayabliTTP(
            config: PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed" }),
            provider: MockTapToPayProvider(),
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )

        for _ in 0 ..< 2 {
            try await ttp.initialize()
            XCTAssertEqual(ttp.sessionState, .ready)
        }

        XCTAssertTrue(registers.values.isEmpty)
        XCTAssertEqual(try attestation.cachedDeviceId(for: "e"), "dev_seed")
    }
}
