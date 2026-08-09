import SwiftUI
import UIKit

/// The Payabli style guide palette, taken from the PAY_Style-Guide Figma file.
///
/// The names below are the token names as the guide spells them, so a colour can be traced back to
/// its source. The Android sample app carries the same values under the same names; the two demos
/// are meant to screenshot as one product.
enum PayabliPalette {
    static let black: UInt32 = 0x00_00_00
    static let white: UInt32 = 0xFF_FF_FF
    static let deepBlue: UInt32 = 0x02_0B_27

    static let blue1: UInt32 = 0x04_C3_FF
    static let blue3: UInt32 = 0xDD_F7_FF
    static let blue4: UInt32 = 0x00_1C_6E

    static let teal2: UInt32 = 0xA7_FC_FF
    static let teal4: UInt32 = 0x00_55_58

    static let cinnamon2: UInt32 = 0xFF_AE_B7
    static let cinnamon4: UInt32 = 0x68_0A_04

    static let lemon1: UInt32 = 0xFF_C8_5C
    static let lemon4: UInt32 = 0x63_42_00

    static let neutral1: UInt32 = 0x13_1D_3A
    static let neutral3: UInt32 = 0x3C_47_6B
    static let neutral4: UInt32 = 0x57_61_80
    static let neutral5: UInt32 = 0x89_92_AC
    static let neutral6: UInt32 = 0xC5_CB_DB
    static let neutral7: UInt32 = 0xEF_F0_F7
    static let neutral8: UInt32 = 0xF9_F9_FF

    /// Two steps the guide does not name, blended between the tones on either side of them.
    static let lightContainerHigh: UInt32 = 0xDD_E0_EB
    static let darkContainerHigh: UInt32 = 0x1A_26_4A
}

/// The roles the demo draws with.
///
/// Each one resolves through a `UIColor` that reads the trait collection, so light and dark are
/// decided at draw time exactly as the system colours these replaced were. Swapping to an asset
/// catalogue would work too; this keeps the whole palette and its role mapping in one readable file,
/// next to the Android file it mirrors.
///
/// Which token plays which role, and why the bright ones are not the filled-button colours: Blue 1
/// is a light cyan, so white text on it clears no contrast bar. It is `primary` in dark, where it
/// sits on a near-black surface, and Blue 4 carries the light scheme's accents at 15.1:1 against
/// white. The guide has no green, so a passing check reads teal; inventing a green would put a
/// colour in the app that appears in no token list.
///
/// Every pair used here was measured with the WCAG formula and clears 4.5:1 in both appearances.
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
