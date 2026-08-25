@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import Security
import XCTest

/// The value `/register` is given to recognize this install across registrations.
///
/// It has to identify one install of one app and keep identifying it, and it is the
/// only thing sent that can. The four properties below are what that means: the
/// same answer every call, the same answer after a reinstall, a different answer
/// for a different app or handset, and the stored value not recoverable from it.
final class InstallIdentifierTests: XCTestCase {
    private let bundleA = "com.acme.checkout"
    private let bundleB = "com.acme.backoffice"

    // MARK: - The same on every call

    func testTheSameStoreAndAppAnswerTheSameValueEveryCall() throws {
        let storage = InMemorySecureStorage()

        let first = try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: bundleA)
        let second = try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: bundleA)

        XCTAssertEqual(first, second, "the device registers again on every call")
        XCTAssertFalse(first.isEmpty)
    }

    /// A reinstall keeps the Keychain and loses everything the app itself held, so
    /// the returning install reads the same Keychain through objects it built fresh.
    ///
    /// Two stores over one backing, not one store asked twice: asked twice, this is
    /// the test above it under another name, and it would pass just as well if what
    /// survived lived in the instance rather than in the Keychain.
    func testAReturningInstallAnswersWhatItAnsweredBefore() throws {
        let keychain = DurableBacking()
        let before = try InstallIdentifier.hardwareId(
            storage: KeychainStandIn(backing: keychain),
            bundleIdentifier: bundleA
        )

        // Everything the install held is gone; the Keychain is not.
        let after = try InstallIdentifier.hardwareId(
            storage: KeychainStandIn(backing: keychain),
            bundleIdentifier: bundleA
        )

        XCTAssertEqual(before, after, "a returning install registers as a device never seen before")
    }

    /// The counterpart, so the test above cannot pass by the value being fixed: a
    /// returning install whose Keychain went too is a new device.
    func testAnInstallWhoseKeychainWentTooIsANewDevice() throws {
        let before = try InstallIdentifier.hardwareId(
            storage: KeychainStandIn(backing: DurableBacking()),
            bundleIdentifier: bundleA
        )
        let after = try InstallIdentifier.hardwareId(
            storage: KeychainStandIn(backing: DurableBacking()),
            bundleIdentifier: bundleA
        )

        XCTAssertNotEqual(before, after)
    }

    /// An install that lost the stored UUID is a new device, and says so.
    func testAnInstallThatLostTheStoredValueAnswersSomethingElse() throws {
        let storage = InMemorySecureStorage()
        let before = try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: bundleA)

        try storage.remove(forKey: PayabliKeychainKey.installId)
        let after = try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: bundleA)

        XCTAssertNotEqual(before, after)
    }

    // MARK: - Different per app

    /// Two apps from one developer are two devices, and nothing else sent alongside
    /// this distinguishes them, so one value for both leaves them indistinguishable.
    func testTwoAppsOnOneHandsetAnswerDifferentValues() throws {
        let storage = InMemorySecureStorage()

        let a = try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: bundleA)
        let b = try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: bundleB)

        XCTAssertNotEqual(a, b, "both apps resolve to one device record")
    }

    /// Two handsets are two devices even for one app.
    func testTwoHandsetsAnswerDifferentValuesForOneApp() throws {
        let a = try InstallIdentifier.hardwareId(
            storage: InMemorySecureStorage(),
            bundleIdentifier: bundleA
        )
        let b = try InstallIdentifier.hardwareId(
            storage: InMemorySecureStorage(),
            bundleIdentifier: bundleA
        )

        XCTAssertNotEqual(a, b)
    }

    // MARK: - What reaches the wire

    /// The stored UUID is never the value sent. A party holding the digest cannot
    /// recover it, which is what lets the same value be sent to a service that keys
    /// a lookup on it.
    func testTheStoredValueIsNotTheValueSent() throws {
        let storage = InMemorySecureStorage()
        let sent = try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: bundleA)

        let stored = try XCTUnwrap(storage.string(forKey: PayabliKeychainKey.installId))
        XCTAssertNotEqual(sent, stored)
        XCTAssertFalse(sent.contains(stored))
        XCTAssertFalse(sent.lowercased().contains(stored.lowercased()))
    }

    /// 128 bits as lowercase hex. The wire field is sized for a serial number.
    func testTheValueIs128BitsOfHex() throws {
        let sent = try InstallIdentifier.hardwareId(
            storage: InMemorySecureStorage(),
            bundleIdentifier: bundleA
        )

        XCTAssertEqual(sent.count, 32)
        XCTAssertTrue(sent.allSatisfy(\.isHexDigit))
        XCTAssertEqual(sent, sent.lowercased())
    }

    // MARK: - Nothing to build from

    /// A blank is refused when the device registers. A value invented here would
    /// differ per call, so every call would register a device and nothing would
    /// report the fault.
    func testNoBundleIdentifierIsBlank() throws {
        XCTAssertEqual(
            try InstallIdentifier.hardwareId(storage: InMemorySecureStorage(), bundleIdentifier: nil),
            ""
        )
        XCTAssertEqual(
            try InstallIdentifier.hardwareId(storage: InMemorySecureStorage(), bundleIdentifier: ""),
            ""
        )
    }

    /// A store that could not be read is raised, not answered as a fresh install.
    /// Answered that way, the UUID is minted again and the device registers again.
    func testAStoreThatCouldNotBeReadIsRaised() throws {
        let storage = InMemorySecureStorage()
        storage.readFailure = KeychainStorage.KeychainError.underlying(errSecInteractionNotAllowed)

        XCTAssertThrowsError(
            try InstallIdentifier.hardwareId(storage: storage, bundleIdentifier: bundleA)
        )
    }
}
