import SwiftUI

/// Renders a small brand badge next to the card-number input.
///
/// v1.0 uses SF Symbols as a neutral placeholder — host apps that prefer
/// official network artwork can supply an image asset named `PayabliBrand_<Brand>`
/// (e.g. `PayabliBrand_Visa`) in their own asset catalog and it will be picked
/// up automatically. PRD FR-1.3 + §15 Future.
@available(iOS 15.0, macOS 12.0, *)
struct CardBrandBadge: View {
    let brand: PaymentValidators.CardBrand

    var body: some View {
        if brand == .unknown {
            EmptyView()
        } else {
            contents
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12))
                )
        }
    }

    @ViewBuilder
    private var contents: some View {
        // Try host-supplied asset first; fall back to SF Symbol + label.
        #if canImport(UIKit)
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 16)
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    @ViewBuilder
    private var fallback: some View {
        HStack(spacing: 4) {
            Image(systemName: sfSymbol)
                .font(.caption2)
            Text(brand.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var assetName: String {
        "PayabliBrand_\(brand.rawValue.replacingOccurrences(of: " ", with: ""))"
    }

    private var sfSymbol: String {
        // SF Symbols doesn't ship network marks; we use a neutral card glyph.
        "creditcard.fill"
    }
}
