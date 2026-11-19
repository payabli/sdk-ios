import SwiftUI
import UIKit

/// The Payabli style guide palette, taken from the PAY_Style-Guide Figma file.
///
/// The names below are the token names as the guide spells them, so a colour can be traced back to
/// its source.
enum PayabliPalette {
    static let black: UInt32 = 0x000000
    static let white: UInt32 = 0xFFFFFF
    static let deepBlue: UInt32 = 0x020B27

    static let blue1: UInt32 = 0x04C3FF
    static let blue3: UInt32 = 0xDDF7FF
    static let blue4: UInt32 = 0x001C6E

    static let teal2: UInt32 = 0xA7FCFF
    static let teal4: UInt32 = 0x005558

    static let cinnamon2: UInt32 = 0xFFAEB7
    static let cinnamon4: UInt32 = 0x680A04

    static let lemon1: UInt32 = 0xFFC85C
    static let lemon4: UInt32 = 0x634200

    static let neutral1: UInt32 = 0x131D3A
    static let neutral3: UInt32 = 0x3C476B
    static let neutral4: UInt32 = 0x576180
    static let neutral5: UInt32 = 0x8992AC
    static let neutral6: UInt32 = 0xC5CBDB
    static let neutral7: UInt32 = 0xEFF0F7
    static let neutral8: UInt32 = 0xF9F9FF

    /// Two steps the guide does not name, blended between the tones on either side of them.
    static let lightContainerHigh: UInt32 = 0xDDE0EB
    static let darkContainerHigh: UInt32 = 0x1A264A
}

/// The roles the demo draws with, resolved per appearance at draw time. White text fails contrast on
/// Blue 1, a light cyan, so it is `primary` only in dark. The guide has no green, so a passing check
/// reads teal. Every pair used here clears 4.5:1 in both appearances.
extension Color {
    // Surfaces.
    static let payabliBackground = dynamic(light: PayabliPalette.neutral8, dark: PayabliPalette.deepBlue)
    static let payabliSurfaceContainer = dynamic(light: PayabliPalette.neutral7, dark: PayabliPalette.neutral1)
    static let payabliSurfaceContainerHigh = dynamic(
        light: PayabliPalette.lightContainerHigh,
        dark: PayabliPalette.darkContainerHigh
    )

    // Text.
    static let payabliOnSurface = dynamic(light: PayabliPalette.neutral1, dark: PayabliPalette.neutral7)
    static let payabliOnSurfaceVariant = dynamic(light: PayabliPalette.neutral3, dark: PayabliPalette.neutral6)

    // Accent.
    static let payabliPrimary = dynamic(light: PayabliPalette.blue4, dark: PayabliPalette.blue1)
    static let payabliOnPrimary = dynamic(light: PayabliPalette.white, dark: PayabliPalette.blue4)
    static let payabliPrimaryContainer = dynamic(light: PayabliPalette.blue3, dark: PayabliPalette.blue4)

    // Lines.
    static let payabliOutline = dynamic(light: PayabliPalette.neutral5, dark: PayabliPalette.neutral4)
    static let payabliOutlineVariant = dynamic(light: PayabliPalette.neutral6, dark: PayabliPalette.neutral3)

    // Status. `success` and `warning` have no system equivalent worth matching, and `error` is here
    // rather than left as `.red` so all three come from the same list.
    static let payabliSuccess = dynamic(light: PayabliPalette.teal4, dark: PayabliPalette.teal2)
    static let payabliWarning = dynamic(light: PayabliPalette.lemon4, dark: PayabliPalette.lemon1)
    static let payabliError = dynamic(light: PayabliPalette.cinnamon4, dark: PayabliPalette.cinnamon2)

    /// The resting tone for a state that is neither good nor bad.
    static let payabliNeutral = dynamic(light: PayabliPalette.neutral4, dark: PayabliPalette.neutral5)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
