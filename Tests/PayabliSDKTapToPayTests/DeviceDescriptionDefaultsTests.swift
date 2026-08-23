@testable import PayabliSDKTapToPay
import XCTest

/// What the SDK reports about the handset it is running on.
final class DeviceDescriptionDefaultsTests: XCTestCase {
    /// The model string, against the same field decoded independently. The wire
    /// value must not change: a device already registered under one model that
    /// starts sending another is a different device to the service.
    func testTheModelIsTheMachineFieldDecodedWhole() {
        var info = utsname()
        uname(&info)
        let expected = withUnsafeBytes(of: &info.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }

        XCTAssertFalse(expected.isEmpty, "uname reported no machine field")
        XCTAssertEqual(AppAttestService.defaultModel(), expected)
    }

    /// A hardware identifier the platform will not give is blank, and blank is
    /// what registration refuses. Anything invented here differs per call, so
    /// every call registers a device and nothing ever reports the fault.
    func testNoHardwareIdentifierIsBlank() {
        XCTAssertEqual(AppAttestService.hardwareId(from: nil), "")
    }

    func testAHardwareIdentifierIsPassedThroughUnchanged() {
        XCTAssertEqual(
            AppAttestService.hardwareId(from: "3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
            "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        )
    }

    /// Whatever the platform gives, the same call twice gives the same answer.
    /// A value invented per call would not, and would register a device each time.
    func testAHardwareIdentifierIsStableAcrossCalls() {
        XCTAssertEqual(AppAttestService.defaultHardwareId(), AppAttestService.defaultHardwareId())
    }

    /// The model carries no trailing control bytes from the 256-byte field.
    func testTheModelCarriesNoControlCharacters() {
        let model = AppAttestService.defaultModel()

        XCTAssertEqual(model, model.trimmingCharacters(in: .controlCharacters))
        XCTAssertFalse(model.isEmpty)
    }
}
