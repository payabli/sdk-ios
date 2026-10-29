import XCTest

/// What the Config tab's support row shows for the session's device ID.
final class SupportDeviceIdTests: XCTestCase {
    private let deviceId = "4da924ef-1c2b-4e5f-8a9b-0c1d2e3f4a5b"

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

    func testAnEmptyDeviceIdReadsUnavailable() {
        let row = SupportDeviceId("")

        XCTAssertEqual(row.shown, "Unavailable")
        XCTAssertNil(row.copyable)
    }

    func testItsDescriptionNeverCarriesTheId() {
        let printed = String(describing: SupportDeviceId(deviceId))
            + String(reflecting: SupportDeviceId(deviceId))

        XCTAssertFalse(printed.contains(deviceId), printed)
    }
}
