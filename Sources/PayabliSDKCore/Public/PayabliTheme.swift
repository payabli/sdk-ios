import CoreGraphics
import Foundation
import SwiftUI

/// Compatibility container for the pre-component theming API.
///
/// New components expose their own SwiftUI style types. This type remains so
/// external code that still calls `configure(config:theme:)` can migrate
/// without an immediate source break.
@objc public final class PayabliTheme: NSObject, Sendable {
    /// Hex color string (e.g. `"#10B981"`) used for primary buttons and accents.
    public let primaryColorHex: String

    /// Corner radius applied to text fields and buttons (in points).
    public let cornerRadius: CGFloat

    /// Custom font family name. Planned/future; unused by current components.
    public let fontName: String?

    public init(
        primaryColorHex: String = "#10B981",
        cornerRadius: CGFloat = 8,
        fontName: String? = nil
    ) {
        self.primaryColorHex = primaryColorHex
        self.cornerRadius = cornerRadius
        self.fontName = fontName
        super.init()
    }

    @objc public static let `default` = PayabliTheme()
}

// MARK: - SwiftUI integration

public extension PayabliTheme {
    /// The primary color resolved as a SwiftUI `Color`.
    var primaryColor: Color {
        Color(hex: primaryColorHex) ?? Color.accentColor
    }

    /// Corner radius as a SwiftUI shape.
    var cornerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius)
    }
}

// MARK: - Hex → Color

extension Color {
    /// Parses a hex color string of the form `#RRGGBB` or `#RRGGBBAA`.
    /// Returns `nil` on invalid input.
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        let red, green, blue, alpha: Double
        if cleaned.count == 6 {
            red = Double((value & 0xFF0000) >> 16) / 255.0
            green = Double((value & 0x00FF00) >> 8) / 255.0
            blue = Double(value & 0x0000FF) / 255.0
            alpha = 1.0
        } else {
            red = Double((value & 0xFF00_0000) >> 24) / 255.0
            green = Double((value & 0x00FF_0000) >> 16) / 255.0
            blue = Double((value & 0x0000_FF00) >> 8) / 255.0
            alpha = Double(value & 0x0000_00FF) / 255.0
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
