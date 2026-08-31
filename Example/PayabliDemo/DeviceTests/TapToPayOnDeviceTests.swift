@testable import PayabliDemo
import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// What this branch changed, exercised against a live paypoint on real hardware.
///
/// Everything up to the tap. `charge()` needs a card held to the phone, so the read
/// is abandoned once the backend has minted a `paymentTransId`, which is the last
/// thing that happens before the reader waits for a card.
///
/// Each test establishes what it needs and assumes nothing about what ran before
/// it. XCTest runs methods in name order by default and does not have to: a run can
/// select one method or reorder them, and a test that reads what its neighbour
/// wrote then passes or fails on that choice rather than on the code.
///
/// These register a device against the paypoint the run names, which is a write.
@MainActor
final class TapToPayOnDeviceTests: XCTestCase {
    // Set in setUp, read by every test: the XCTest shape for a fixture that cannot
    // exist at init. Was accepted through the lint baseline until this line moved.
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var named: LiveTarget!

    override func setUp() async throws {
        try await super.setUp()
        named = try LiveEnvironment.named()
        LiveEnvironment.announce(named)
        _ = try await LiveEnvironment.requireAToken()
    }

    private func makeTTP() throws -> PayabliTTP {
        try PayabliTTP(
            accessToken: Secrets.placeholderAccessToken,
            tokenProvider: { try await Secrets.fetchAccessToken() },
            entryPoint: named.entry,
            appId: Secrets.appId,
            environment: named.environment
        )
    }

    private func attestation() throws -> AppAttestService {
        AppAttestService(
            transport: PayabliSession(config: try LiveEnvironment.config(for: named)).transport,
            attestor: RealAppAttestor(),
            storage: KeychainStorage()
        )
    }

    /// Brings this device to `.ready` and answers the handle it holds, so a test
    /// that needs an enrolled device says so rather than reading what another one
    /// left behind.
    ///
    /// A paypoint that issues activation codes leaves a device it has not seen
    /// pending, and no code can be minted from in here, so a run against one needs
    /// `PAYABLI_ACTIVATION_CODE`. That is reported as a skip rather than a pass.
    ///
    /// The session it readied comes back with the handle, because preparing a reader
    /// on a device costs minutes: a caller that made its own would pay for a second
    /// one to do the same thing.
    @discardableResult
    private func enrolledDevice() async throws -> (session: PayabliTTP, handle: String) {
        let ttp = try makeTTP()
        do {
            try await ttp.initialize()
        } catch PayabliTTPError.devicePendingActivation {
            let code = ProcessInfo.processInfo.environment["PAYABLI_ACTIVATION_CODE"] ?? ""
            guard !code.isEmpty else {
                throw XCTSkip(
                    "this device is pending activation on \(named.entry); "
                        + "set PAYABLI_ACTIVATION_CODE to a code minted for its handle"
                )
            }
            do {
                try await ttp.activateDevice(activationCode: code)
            } catch let error as PayabliTTPError {
                // A code is minted for one handle. A device that registered again
                // since holds a different one, and no code for it can be obtained
                // from in here, so this is the run's state rather than a defect.
                guard case let .activationFailed(reason) = error,
                      reason.localizedCaseInsensitiveContains("no active challenge")
                else {
                    throw error
                }
                throw XCTSkip(
                    "PAYABLI_ACTIVATION_CODE was minted for another handle; "
                        + "mint one for the handle testReportTheHandleThisDeviceHolds prints"
                )
            }
            try await ttp.initialize()
        }
        XCTAssertEqual(ttp.sessionState, .ready, "the session never became ready")
        let handle = try XCTUnwrap(
            try attestation().cachedDeviceId(for: named.entry),
            "reaching ready stored no binding for \(named.entry)"
        )
        return (ttp, handle)
    }

    /// Reaching `.ready` stores a binding that names this paypoint.
    func testReachingReadyStoresABindingForThisPaypoint() async throws {
        let held = try await enrolledDevice().handle

        let stored = try XCTUnwrap(
            try KeychainStorage().string(forKey: PayabliKeychainKey.deviceBindings),
            "reaching ready stored no bindings item"
        )
        XCTAssertTrue(stored.contains(named.entry), "the stored binding does not name this paypoint")
        XCTAssertFalse(held.isEmpty)
        LiveEnvironment.reportIdentifier("DEVICE_HANDLE", held, env: named.name)
    }

    /// A second session holds the handle the first one did, which is the claim: a
    /// device registers once for a paypoint rather than once per call.
    ///
    /// Both sessions in one test, so the reuse does not rest on the order two tests
    /// happen to run in.
    ///
    /// This does not drop the binding first, and so does not prove the first session
    /// was the cold one. It cannot: dropping it makes the next registration mint a
    /// handle, an activation code is minted for a handle, and a paypoint that gates
    /// new devices then needs a code that could only be obtained after the drop.
    /// The cold sequence is what enrolled this device, and re-running it needs a
    /// person with the handle in hand.
    func testTheSessionAfterAnEnrolmentHoldsTheSameHandle() async throws {
        let store = try attestation()
        let first = try await enrolledDevice().handle

        let second = try makeTTP()
        try await second.initialize()

        XCTAssertEqual(second.sessionState, .ready)
        XCTAssertEqual(
            try store.cachedDeviceId(for: named.entry),
            first,
            "a second session registered another device for this paypoint"
        )
    }

    /// The paypoint is part of the binding: this device is not enrolled for one it
    /// never registered against, and asking does not disturb the one it did.
    func testAnotherPaypointIsNotThisDevicesEnrolment() async throws {
        let held = try await enrolledDevice().handle
        let store = try attestation()

        let other = "\(named.entry)_notARealPaypoint"
        let enrolledElsewhere = try await store.isAttested(for: other)
        XCTAssertFalse(enrolledElsewhere)
        XCTAssertNil(try store.cachedDeviceId(for: other))
        XCTAssertEqual(try store.cachedDeviceId(for: named.entry), held)
    }

    /// Reports the handle this device holds, registering first if it holds none.
    ///
    /// An activation code is minted for a handle, and a paypoint whose card-present
    /// service is not configured declines the service's own device list, so this is
    /// the way to learn one. Registration stores the binding before pending
    /// activation is surfaced, so a device that cannot reach `.ready` still has a
    /// handle to report.
    func testReportTheHandleThisDeviceHolds() async throws {
        let store = try attestation()
        if try store.cachedDeviceId(for: named.entry) == nil {
            _ = try? await makeTTP().initialize()
        }
        let held = try XCTUnwrap(
            try store.cachedDeviceId(for: named.entry),
            "this device holds no binding for \(named.entry) and registering stored none"
        )
        LiveEnvironment.reportIdentifier("DEVICE_HANDLE", held, env: named.name)
    }

    /// The value registration identifies this install by is the digest, is the same
    /// on every call, and is not the stored UUID.
    func testTheRegistrationIdentifierIsTheDigest() throws {
        let storage = KeychainStorage()
        let first = try InstallIdentifier.hardwareId(storage: storage)
        let second = try InstallIdentifier.hardwareId(storage: storage)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 32, "expected 128 bits of lowercase hex")
        XCTAssertNil(first.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdef").inverted))

        let stored = try XCTUnwrap(storage.string(forKey: PayabliKeychainKey.installId))
        XCTAssertNotEqual(first, stored)
        LiveEnvironment.reportIdentifier("HARDWARE_ID", first, env: named.name)
    }

    /// A reader that reached `.ready` can be re-prepared without re-attesting,
    /// which is the path a host re-entry takes.
    func testReinitializeKeepsTheBinding() async throws {
        let (ttp, before) = try await enrolledDevice()

        try await ttp.reinitializeIfNeeded()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertEqual(try attestation().cachedDeviceId(for: named.entry), before)
    }

    /// A charge reaches the tap with the customer the demo's setting names.
    ///
    /// `charge()` is three steps: `POST /MoneyIn/initiate`, the tap, then
    /// `PATCH /MoneyIn/update`. Only the tap needs a person, so stopping at
    /// `.ready` leaves the initiate untested, and the initiate is where the
    /// customer, the amount and the device handle are sent.
    func testAChargeReachesTheTapWithTheDemoCustomer() async throws {
        try await assertChargeReachesTheTap(
            customer: TapToPayDemoCustomer.customerData,
            label: "demoCustomer"
        )
    }

    /// The same, with no customer. A paypoint that matches on an identifier refuses
    /// this at the initiate, before any card is presented.
    func testAChargeWithNoCustomerIsRefusedBeforeTheTap() async throws {
        try await assertChargeIsRefusedBeforeTheTap(
            customer: PayabliTTPCustomerData(),
            label: "noCustomer"
        )
    }

    /// Drives `charge()` and returns once the backend has minted a
    /// `paymentTransId`, which is the last thing before the reader waits for a card.
    private func assertChargeReachesTheTap(
        customer: PayabliTTPCustomerData,
        label: String
    ) async throws {
        let outcome = try await runChargeToTheTap(customer: customer, label: label)
        XCTAssertEqual(
            outcome.result,
            .completed,
            "the charge never reached the tap with \(label): \(outcome.reported)"
        )
    }

    /// The other direction: the initiate refuses this and no card is ever asked for.
    private func assertChargeIsRefusedBeforeTheTap(
        customer: PayabliTTPCustomerData,
        label: String
    ) async throws {
        let outcome = try await runChargeToTheTap(customer: customer, label: label)
        XCTAssertNotEqual(
            outcome.result,
            .completed,
            "a charge naming nobody reached the tap on a paypoint that matches on an identifier"
        )
        XCTAssertTrue(
            outcome.reported.lowercased().contains("customer"),
            "refused for something other than the customer: \(outcome.reported)"
        )
    }

    private func runChargeToTheTap(
        customer: PayabliTTPCustomerData,
        label: String
    ) async throws -> (result: XCTWaiter.Result, reported: String) {
        let (ttp, _) = try await enrolledDevice()

        let stream = ttp.events()
        let reachedTheTap = expectation(description: "the charge reached the tap")
        let seen = OutcomeBox()

        let collector = Task {
            for await event in stream {
                if case .chargeInitiated = event {
                    seen.recordInitiated()
                    reachedTheTap.fulfill()
                    return
                }
            }
        }

        let charging = Task { @MainActor in
            do {
                _ = try await ttp.charge(
                    type: .sale,
                    paymentDetails: PayabliTTPPaymentDetails(amount: 1.00),
                    customer: customer,
                    orderDescription: "device tests"
                )
            } catch {
                seen.recordTerminal(error.localizedDescription)
            }
        }

        let result = await XCTWaiter().fulfillment(of: [reachedTheTap], timeout: 30)

        // The tap is a person's to make, so the read is ended here. Cancelling the
        // task is not enough on its own: the reader keeps its sheet up waiting for a
        // card, and the next test cannot prepare a reader while it is there, so a
        // run wedges on whichever charge test happens to go first. `cancelReading`
        // is what closes it, and the facade offers no public way to reach it.
        await ttp.provider.cancelReading()
        charging.cancel()
        collector.cancel()
        _ = await charging.value

        // Names what was asserted, not only what the charge last threw: this test
        // ends the read itself, so a run that reached the tap still throws.
        LiveEnvironment.report(
            "PAYABLI_CHARGE env=\(named.name) customer=\(label) "
                + "asserted=\(result == .completed ? "reachedTheTap" : "didNotReachTheTap") \(seen.value)"
        )
        return (result, seen.value)
    }
}

/// What a charge run saw, written from one task and read from another: whether it
/// reached the tap, and what it last threw.
///
/// Two fields rather than one, because this test ends the read itself once the tap
/// is reached. The charge throws even on a run that got there, and that throw is not
/// the verdict.
private final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var initiated = false
    private var terminal: String?

    /// `terminal` is whatever the charge threw, the cancellation this test performs
    /// itself included.
    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return "reachedTheTap=\(initiated ? "yes" : "no") terminal=\(terminal ?? "none")"
    }

    /// Called on `chargeInitiated`, the last event before the reader waits for a card.
    func recordInitiated() {
        lock.lock()
        defer { lock.unlock() }
        initiated = true
    }

    func recordTerminal(_ outcome: String) {
        lock.lock()
        defer { lock.unlock() }
        terminal = outcome
    }
}
