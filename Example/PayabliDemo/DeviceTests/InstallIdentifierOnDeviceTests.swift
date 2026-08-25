@testable import PayabliSDKTapToPay
import Security
import XCTest

/// The value `/register` receives, measured against the Keychain the device
/// actually has.
///
/// The package's own tests answer these questions over a stand-in, which can only
/// show that the code reads what it was given. Whether a Keychain item outlives the
/// app's container is the platform's answer, and it is the whole reason the
/// identifier is built from a stored UUID rather than from the platform's vendor
/// identifier.
final class InstallIdentifierOnDeviceTests: XCTestCase {
    /// Everything except the install-cycle report runs over its own service. The
    /// checks below delete the stored value, and doing that to the SDK's own item
    /// would change the identity of the install the cycle is measuring.
    private var scratch = ""
    private var storage = KeychainStorage()

    override func setUp() {
        super.setUp()
        scratch = "com.payabli.devicetests.\(UUID().uuidString)"
        storage = KeychainStorage(service: scratch)
    }

    override func tearDown() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: scratch
        ] as CFDictionary)
        super.tearDown()
    }

    func testTheSameAnswerOnEveryCall() throws {
        let first = try InstallIdentifier.hardwareId(storage: storage)
        let second = try InstallIdentifier.hardwareId(storage: storage)
        XCTAssertFalse(first.isEmpty, "nothing was built from")
        XCTAssertEqual(first, second)
    }

    /// The stored UUID is what survives, and it is what never leaves the device.
    func testTheStoredValueIsNotWhatIsSent() throws {
        let sent = try InstallIdentifier.hardwareId(storage: storage)
        let stored = try XCTUnwrap(
            storage.string(forKey: PayabliKeychainKey.installId),
            "the identifier was built without minting a stored value"
        )
        XCTAssertNotEqual(sent, stored)
        XCTAssertFalse(sent.contains(stored))
    }

    /// A returning install is recognized as itself only if the stored value is
    /// still there, so losing it is what a reinstall must not do.
    func testANewStoredValueMeansANewIdentifier() throws {
        let before = try InstallIdentifier.hardwareId(storage: storage)
        try storage.remove(forKey: PayabliKeychainKey.installId)
        let after = try InstallIdentifier.hardwareId(storage: storage)
        XCTAssertNotEqual(before, after)
    }

    /// Reports this install's identifier, read from the SDK's own store, for a
    /// caller that can see two runs. Run it, uninstall the app, install it again,
    /// run it again: the two lines must match, and if they do not, a returning
    /// install registers as a device that has never been seen.
    ///
    /// It asserts what it can on its own — that there is a value to compare — and
    /// leaves the comparison to the caller, since a single run cannot span an
    /// uninstall.
    ///
    /// The value needs `PAYABLI_REPORT_IDENTIFIERS`, as every device identifier a
    /// run prints does: this one is stable per install, and Xcode and CI retain what
    /// a test writes.
    func testReportTheIdentifierForAnInstallCycle() throws {
        let id = try InstallIdentifier.hardwareId(storage: KeychainStorage())
        XCTAssertFalse(id.isEmpty, "nothing was built from")
        LiveEnvironment.reportIdentifier("HARDWARE_ID", id, env: "install-cycle")
    }
}
