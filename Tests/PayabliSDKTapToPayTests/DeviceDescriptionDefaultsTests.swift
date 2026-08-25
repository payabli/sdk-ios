@testable import PayabliSDKTapToPay
import XCTest

/// What the SDK reports about the handset it is running on.
final class DeviceDescriptionDefaultsTests: XCTestCase {
    /// The model string, against the same field decoded independently. The wire
    /// value must not change: a device already registered under one model that
    /// starts sending another is a different device to the service.
    func testTheModelIsTheMachineFieldDecodedWhole() throws {
        var info = utsname()
        uname(&info)
        let expected = withUnsafeBytes(of: &info.machine) { raw -> String? in
            let bytes = raw.prefix { $0 != 0 }
            return String(bytes: bytes, encoding: .utf8)
        }

        let machine = try XCTUnwrap(expected, "the machine field is not UTF-8")
        XCTAssertFalse(machine.isEmpty, "uname reported no machine field")
        XCTAssertEqual(AppAttestService.defaultModel(), machine)
    }

    /// The model carries no trailing control bytes from the 256-byte field.
    func testTheModelCarriesNoControlCharacters() {
        let model = AppAttestService.defaultModel()

        XCTAssertEqual(model, model.trimmingCharacters(in: .controlCharacters))
        XCTAssertFalse(model.isEmpty)
    }
}
