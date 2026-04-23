import XCTest
import SwiftUI
@testable import PayabliSDKCore

final class PayabliThemeTests: XCTestCase {
    func testDefaultThemeValues() {
        let theme = PayabliTheme.default
        XCTAssertEqual(theme.primaryColorHex, "#10B981")
        XCTAssertEqual(theme.cornerRadius, 8)
        XCTAssertNil(theme.fontName)
    }

    func testHexColorParsingRGB() {
        XCTAssertNotNil(Color(hex: "#FF0000"))
        XCTAssertNotNil(Color(hex: "FF0000"))
        XCTAssertNotNil(Color(hex: "#10B981"))
    }

    func testHexColorParsingRGBA() {
        XCTAssertNotNil(Color(hex: "#FF0000FF"))
    }

    func testHexColorRejectsInvalid() {
        XCTAssertNil(Color(hex: "#12"))
        XCTAssertNil(Color(hex: "not-a-color"))
        XCTAssertNil(Color(hex: "#ZZZZZZ"))
    }
}
