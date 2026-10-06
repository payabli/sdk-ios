@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// What the key check at `initialize` does with each answer the platform gives.
final class AppAttestKeyCheckTests: XCTestCase {
    /// `XCTAssertTrue` takes an autoclosure, which cannot await, so the answer is
    /// read first and asserted second.
    private func assertAttested(
        _ sut: AppAttestService,
        _ entry: String,
        _ expected: Bool,
        _ message: String = "",
        line: UInt = #line
    ) async throws {
        let actual = try await sut.isAttested(for: entry)
        XCTAssertEqual(actual, expected, message, line: line)
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
            try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
            let (sut, attestor, _) = try AttestFixture.makeService(storage: storage)
            attestor.generateAssertionError = NSError(
                domain: AppAttestService.deviceCheckErrorDomain,
                code: code
            )

            try await assertAttested(sut, "myEntry", false, "code \(code)")

            XCTAssertNil(
                try sut.binding(for: "myEntry"),
                "a binding naming a key that is gone has to be dropped, not asked again every start"
            )
        }
    }

    /// A key that signs is a key this device holds.
    func testABindingWhoseKeySignsIsAnEnrolment() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
        let (sut, _, _) = try AttestFixture.makeService(storage: storage)

        try await assertAttested(sut, "myEntry", true)
        XCTAssertEqual(try sut.cachedDeviceId(for: "myEntry"), "dev")
    }

    /// Asking about a paypoint with no binding asks the platform nothing: there is
    /// no key to ask about, and a signature attempt would be wasted.
    func testNoBindingAsksThePlatformNothing() async throws {
        let (sut, attestor, _) = try AttestFixture.makeService()

        try await assertAttested(sut, "myEntry", false)

        XCTAssertEqual(attestor.generateAssertionCalls, 0)
    }

    /// A check that cannot tell whether the key works stops: re-enrolling costs an enrolment for a key
    /// that may be working, and proceeding signs with one that may not be.
    func testAKeyCheckThatCannotTellStopsAndKeepsTheBinding() async throws {
        let failures = [
            NSError(domain: AppAttestService.deviceCheckErrorDomain, code: 0),
            NSError(domain: AppAttestService.deviceCheckErrorDomain, code: 4),
            NSError(domain: NSOSStatusErrorDomain, code: -1)
        ]
        for failure in failures {
            let storage = InMemorySecureStorage()
            try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
            let (sut, attestor, _) = try AttestFixture.makeService(storage: storage)
            attestor.generateAssertionError = failure

            await assertKeyCheckThrows(sut, .deviceKeyUnavailable, "\(failure.domain) \(failure.code)")
            XCTAssertNotNil(try sut.binding(for: "myEntry"), "\(failure.domain) \(failure.code)")
        }
    }

    /// A phone that cannot produce an assertion at all is not a key that went away.
    func testAPhoneThatCannotSignStopsAsUnsupportedAndKeepsTheBinding() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
        let (sut, attestor, _) = try AttestFixture.makeService(storage: storage)
        attestor.generateAssertionError = NSError(domain: AppAttestService.deviceCheckErrorDomain, code: 1)

        await assertKeyCheckThrows(sut, .deviceSetupUnsupported)
        XCTAssertNotNil(try sut.binding(for: "myEntry"))
    }

    func testAPhoneWithoutAppAttestCannotBeSetUp() async throws {
        let (sut, attestor, _) = try AttestFixture.makeService(storage: InMemorySecureStorage())
        attestor.isSupported = false

        do {
            _ = try await sut.attest(entry: "myEntry")
            XCTFail("an unsupported phone was attested")
        } catch {
            XCTAssertEqual((error as? TapToPayError)?.type, .deviceSetupUnsupported, "\(error)")
        }
    }

    private func assertKeyCheckThrows(
        _ sut: AppAttestService,
        _ type: PayabliErrorType,
        _ message: String = "",
        line: UInt = #line
    ) async {
        do {
            _ = try await sut.isAttested(for: "myEntry")
            XCTFail("the key check proceeded. \(message)", line: line)
        } catch {
            XCTAssertEqual((error as? TapToPayError)?.type, type, "\(error) \(message)", line: line)
        }
    }

    /// The probe suspends, so the answer can arrive after another attempt has
    /// enrolled this paypoint. What it refuses is the binding it asked about, and
    /// dropping by entry point alone would take the newer one instead, leaving a
    /// device that enrolled moments ago holding nothing.
    func testAProbeAnsweringLateDropsOnlyTheBindingItAskedAbout() async throws {
        let storage = InMemorySecureStorage()
        let (sut, attestor, _) = try AttestFixture.makeService(storage: storage)

        // What the probe read, before it went away to ask.
        let probed = AttestedDevice(entry: "myEntry", deviceId: "dev_old", keyId: "old_key")

        // What the entry point holds by the time the answer lands.
        try sut.remember(AttestedDevice(entry: "myEntry", deviceId: "dev_new", keyId: "new_key"))
        try sut.rememberPendingKey("pending_for_new", for: "myEntry")

        attestor.generateAssertionError = NSError(
            domain: AppAttestService.deviceCheckErrorDomain,
            code: 2,
            userInfo: nil
        )

        let stillHeld = try await sut.keyIsStillHeld(probed)

        XCTAssertFalse(stillHeld, "the probed key was refused and the answer said otherwise")
        XCTAssertEqual(
            try sut.binding(for: "myEntry")?.deviceId,
            "dev_new",
            "the newer binding was dropped for a key it never named"
        )
        XCTAssertEqual(
            try sut.pendingKey(for: "myEntry"),
            "pending_for_new",
            "a pending key belonging to a newer attempt was dropped"
        )
    }
}
