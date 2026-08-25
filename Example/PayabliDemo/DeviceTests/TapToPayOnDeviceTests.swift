@testable import PayabliDemo
import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// What this branch changed, exercised against a live paypoint on real hardware.
///
/// Everything up to the tap. `charge()` needs a card held to the phone, so it is a
/// written step somebody walks, and nothing on this branch touches the tap itself.
///
/// These register a device against the paypoint the run names, which is a write.
@MainActor
final class TapToPayOnDeviceTests: XCTestCase {
    private var named: (environment: PayabliEnvironment, entry: String, name: String)!

    override func setUp() async throws {
        try await super.setUp()
        named = try LiveEnvironment.named()
        LiveEnvironment.announce(named)
        _ = try await LiveEnvironment.requireAToken()
    }

    private func makeTTP() -> PayabliTTP {
        PayabliTTP(
            accessToken: Secrets.placeholderAccessToken,
            tokenProvider: { try await Secrets.fetchAccessToken() },
            entryPoint: named.entry,
            appId: Secrets.appId,
            environment: named.environment
        )
    }

    /// Spends an activation code on this device, when the run supplies one.
    ///
    /// A paypoint that issues codes leaves a newly registered device pending, and
    /// nothing after this reaches `.ready` until it is activated. The code is
    /// short-lived and issued out of band, so it arrives in the environment rather
    /// than living in the file.
    func test0ActivateThisDeviceWhenACodeIsGiven() async throws {
        let code = ProcessInfo.processInfo.environment["PAYABLI_ACTIVATION_CODE"] ?? ""
        try XCTSkipIf(code.isEmpty, "no PAYABLI_ACTIVATION_CODE for this run")

        let ttp = makeTTP()
        _ = try? await ttp.initialize()
        guard ttp.sessionState == .pendingActivation else {
            XCTAssertEqual(ttp.sessionState, .ready, "this device is neither pending nor ready")
            return
        }

        try await ttp.activateDevice(activationCode: code)
        XCTAssertEqual(ttp.sessionState, .idle, "activation left the session somewhere else")

        try await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .ready, "an activated device did not reach ready")
        print("PAYABLI_ACTIVATED env=\(named.name)")
    }

    /// A cold start enrols this device against the paypoint and reaches `.ready`.
    ///
    /// The whole sequence on real hardware: App Attest mints and attests a key,
    /// `/register` is given the digest this branch derives, `/config` is answered
    /// for the binding, and the reader is prepared.
    func testAColdStartEnrolsAndReachesReady() async throws {
        let ttp = makeTTP()
        try await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertTrue(ttp.isReady)

        let held = try XCTUnwrap(
            try KeychainStorage().string(forKey: PayabliKeychainKey.deviceBindings),
            "reaching ready stored no binding"
        )
        XCTAssertTrue(held.contains(named.entry), "the stored binding does not name this paypoint")
    }

    /// A second session on the same device reuses the binding rather than
    /// registering again, which is the defect this ticket names.
    ///
    /// Runs after the cold start above, so it reads what that one wrote. The
    /// device this build registered is the one it keeps using.
    func testBAWarmStartReusesTheBinding() async throws {
        let attestation = AppAttestService(
            transport: PayabliSession(config: LiveEnvironment.config(for: named)).transport,
            attestor: RealAppAttestor(),
            storage: KeychainStorage()
        )

        let before = try XCTUnwrap(
            try attestation.cachedDeviceId(for: named.entry),
            "no binding to warm-start from; the cold-start test has to run first"
        )
        let enrolled = try await attestation.isAttested(for: named.entry)
        XCTAssertTrue(
            enrolled,
            "a binding this device holds, whose key the platform still signs with, read as not enrolled"
        )

        let ttp = makeTTP()
        try await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertEqual(
            try attestation.cachedDeviceId(for: named.entry),
            before,
            "a warm start registered a second device for this paypoint"
        )
        print("PAYABLI_DEVICE_HANDLE env=\(named.name) deviceId=\(before)")
    }

    /// The paypoint is part of the binding: this device is not enrolled for a
    /// paypoint it never registered against, and asking does not disturb the one
    /// it did.
    func testCAnotherPaypointIsNotThisDevicesEnrolment() async throws {
        let attestation = AppAttestService(
            transport: PayabliSession(config: LiveEnvironment.config(for: named)).transport,
            attestor: RealAppAttestor(),
            storage: KeychainStorage()
        )
        let held = try XCTUnwrap(try attestation.cachedDeviceId(for: named.entry))

        let other = "\(named.entry)_notARealPaypoint"
        let enrolledElsewhere = try await attestation.isAttested(for: other)
        XCTAssertFalse(enrolledElsewhere)
        XCTAssertNil(try attestation.cachedDeviceId(for: other))
        XCTAssertEqual(try attestation.cachedDeviceId(for: named.entry), held)
    }

    /// The value registration identifies this install by is the digest, is the
    /// same on every call, and is not the stored UUID.
    func testDTheRegistrationIdentifierIsTheDigest() throws {
        let storage = KeychainStorage()
        let first = try InstallIdentifier.hardwareId(storage: storage)
        let second = try InstallIdentifier.hardwareId(storage: storage)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 32, "expected 128 bits of lowercase hex")
        XCTAssertNil(first.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdef").inverted))

        let stored = try XCTUnwrap(storage.string(forKey: PayabliKeychainKey.installId))
        XCTAssertNotEqual(first, stored)
        print("PAYABLI_HARDWARE_ID env=\(named.name) hardwareId=\(first)")
    }

    /// A reader that reached `.ready` can be re-prepared without re-attesting,
    /// which is the path a host re-entry takes.
    func testEReinitializeKeepsTheBinding() async throws {
        let attestation = AppAttestService(
            transport: PayabliSession(config: LiveEnvironment.config(for: named)).transport,
            attestor: RealAppAttestor(),
            storage: KeychainStorage()
        )
        let before = try XCTUnwrap(try attestation.cachedDeviceId(for: named.entry))

        let ttp = makeTTP()
        try await ttp.initialize()
        try await ttp.reinitializeIfNeeded()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertEqual(try attestation.cachedDeviceId(for: named.entry), before)
    }
}
