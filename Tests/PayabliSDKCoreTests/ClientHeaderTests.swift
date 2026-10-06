@testable import PayabliSDKCore
import XCTest

final class ClientHeaderTests: XCTestCase {
    private func facts(
        sdkVersion: String = "0.1.0",
        osVersion: String = "26.6.2",
        hardware: String = "iPhone12,3",
        locale: String = "en-US",
        deviceId: String? = "0123456789abcdef0123456789abcdef"
    ) -> ClientFacts {
        ClientFacts(
            sdkVersion: sdkVersion,
            osVersion: osVersion,
            hardware: hardware,
            deviceId: { deviceId },
            locale: { locale }
        )
    }

    func testEveryMemberInTheFixedOrderAsExactOctets() {
        XCTAssertEqual(
            ClientHeader.value(of: facts()),
            #"sdk-version="0.1.0", platform=ios, os-version="26.6.2", hardware="iPhone12,3", "#
                + #"locale="en-US", device-id="0123456789abcdef0123456789abcdef""#
        )
    }

    func testNoDeviceIdMeansNoDeviceIdMember() {
        XCTAssertEqual(
            ClientHeader.value(of: facts(deviceId: nil)),
            #"sdk-version="0.1.0", platform=ios, os-version="26.6.2", hardware="iPhone12,3", locale="en-US""#
        )
    }

    func testABlankValueLeavesItsMemberOutAndTheRestKeepTheirOrder() {
        XCTAssertEqual(
            ClientHeader.value(of: facts(osVersion: " ", deviceId: "")),
            #"sdk-version="0.1.0", platform=ios, hardware="iPhone12,3", locale="en-US""#
        )
    }

    func testAValueOutsidePrintableASCIIIsLeftOutNeverTranscoded() {
        XCTAssertEqual(
            ClientHeader.value(of: facts(hardware: "iPhone Ä", deviceId: nil)),
            #"sdk-version="0.1.0", platform=ios, os-version="26.6.2", locale="en-US""#
        )
        XCTAssertEqual(
            ClientHeader.value(of: facts(hardware: "tab\there", deviceId: nil)),
            #"sdk-version="0.1.0", platform=ios, os-version="26.6.2", locale="en-US""#
        )
    }

    func testAQuoteAndABackslashAreEscapedInsideTheString() {
        XCTAssertEqual(
            ClientHeader.value(of: facts(hardware: #"a"b\c"#, deviceId: nil)),
            #"sdk-version="0.1.0", platform=ios, os-version="26.6.2", hardware="a\"b\\c", locale="en-US""#
        )
    }

    func testTheLocaleAndTheDeviceIdAreReadOnEveryCall() {
        let changing = Changing()
        let facts = ClientFacts(
            sdkVersion: "0.1.0",
            osVersion: "26.6.2",
            hardware: "iPhone12,3",
            deviceId: { changing.deviceId },
            locale: { changing.locale }
        )

        let first = ClientHeader.value(of: facts)
        changing.locale = "es-MX"
        changing.deviceId = "0123456789abcdef0123456789abcdef"
        let second = ClientHeader.value(of: facts)

        XCTAssertEqual(
            first,
            #"sdk-version="0.1.0", platform=ios, os-version="26.6.2", hardware="iPhone12,3", locale="en-US""#
        )
        XCTAssertEqual(
            second,
            #"sdk-version="0.1.0", platform=ios, os-version="26.6.2", hardware="iPhone12,3", "#
                + #"locale="es-MX", device-id="0123456789abcdef0123456789abcdef""#
        )
    }
}

private final class Changing: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLocale = "en-US"
    private var storedDeviceId: String?

    var locale: String {
        get { lock.withLock { storedLocale } }
        set { lock.withLock { storedLocale = newValue } }
    }

    var deviceId: String? {
        get { lock.withLock { storedDeviceId } }
        set { lock.withLock { storedDeviceId = newValue } }
    }
}
