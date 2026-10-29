import XCTest

/// What the Config tab's support row shows for the session's device ID.
final class SupportDeviceIdTests: XCTestCase {
    private let deviceId = "a1b2c3d4e5f60718293a4b5c6d7e8f90"

    func testTheSessionsDeviceIdIsShownAndCopyable() {
        let row = SupportDeviceId(deviceId)

        XCTAssertEqual(row.shown, deviceId)
        XCTAssertEqual(row.copyable, deviceId)
    }

    func testAMissingDeviceIdReadsUnavailableAndOffersNoCopy() {
        let row = SupportDeviceId(nil)

        XCTAssertEqual(row.shown, "Unavailable")
        XCTAssertNil(row.copyable)
    }

    func testBeforeTheSessionAnswersTheRowSaysItIsReading() {
        let row = SupportDeviceId.reading

        XCTAssertEqual(row.shown, "Reading…")
        XCTAssertNil(row.copyable)
    }

    func testItsDescriptionNeverCarriesTheId() {
        let printed = String(describing: SupportDeviceId(deviceId))
            + String(reflecting: SupportDeviceId(deviceId))

        XCTAssertFalse(printed.contains(deviceId), printed)
    }
}
