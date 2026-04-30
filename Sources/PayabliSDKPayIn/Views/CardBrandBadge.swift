import SwiftUI

/// Renders a brand badge next to the card-number input.
///
/// Asset resolution order:
/// 1. **SDK-bundled asset** (`.module`): `brand-visa`, `brand-mastercard`,
///    `brand-amex`, `brand-discover`. Shipped under
///    `Sources/PayabliSDKPayIn/Resources/PayabliBrandAssets.xcassets` — see
///    that folder's README for the drop-in workflow.
/// 2. **Host-app override** (main bundle): `PayabliBrand_Visa`,
///    `PayabliBrand_Mastercard`, etc. Lets a host app replace the shipped
///    artwork without rebuilding the SDK.
/// 3. **SF Symbol + text fallback** — used when neither asset is present
///    (e.g. unit-test builds on macOS, or a brand whose asset hasn't been
///    dropped in yet).
///
/// PRD FR-1.3 + §15 Future.
@available(iOS 15.0, macOS 12.0, *)
struct CardBrandBadge: View {
    let brand: PaymentValidators.CardBrand

    /// Target render height in points. 22pt aligns with the floating-label row
    /// in `CardFormView`.
    var height: CGFloat = 22

    var body: some View {
        if brand == .unknown {
            EmptyView()
        } else if let image = resolvedImage {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .accessibilityLabel(brand.rawValue)
        } else {
            fallback
        }
    }

    // MARK: - Resolution

    private var resolvedImage: Image? {
        #if canImport(UIKit)
        if UIImage(named: bundledName, in: .module, with: nil) != nil {
            return Image(bundledName, bundle: .module)
        }
        if UIImage(named: hostOverrideName) != nil {
            return Image(hostOverrideName)
        }
        return nil
        #else
        return nil
        #endif
    }

    @ViewBuilder
    private var fallback: some View {
        HStack(spacing: 4) {
            Image(systemName: "creditcard.fill").font(.caption2)
            Text(brand.rawValue).font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12))
        )
        .accessibilityLabel(brand.rawValue)
    }

    private var bundledName: String {
        switch brand {
        case .visa: return "brand-visa"
        case .mastercard: return "brand-mastercard"
        case .amex: return "brand-amex"
        case .discover: return "brand-discover"
        case .unknown: return ""
        }
    }

    private var hostOverrideName: String {
        "PayabliBrand_\(brand.rawValue.replacingOccurrences(of: " ", with: ""))"
    }
}
