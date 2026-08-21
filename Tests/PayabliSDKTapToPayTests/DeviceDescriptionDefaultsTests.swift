@testable import PayabliSDKTapToPay
import XCTest

/// What the SDK reports about the handset it is running on.
final class DeviceDescriptionDefaultsTests: XCTestCase {
    /// A hardware identifier the platform will not give is blank, and blank is
    /// what registration refuses. Anything invented here differs per call, so
    /// every call registers a device and nothing ever reports the fault.
    func testAHardwareIdentifierIsStableAcrossCalls() {
        let first = AppAttestService.defaultHardwareId()
        let second = AppAttestService.defaultHardwareId()

        XCTAssertEqual(first, second)
    }
}
