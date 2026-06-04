import SwiftUI

public struct PayabliPayInPaymentFlowCardBrandIcon: View {
    private let brand: PayabliPayInPaymentFlowCardBrand
    private let borderColor: Color
    private let emptyBackgroundColor: Color
    private let fallbackIconColor: Color

    public init(
        brand: PayabliPayInPaymentFlowCardBrand,
        borderColor: Color,
        emptyBackgroundColor: Color = Color(uiColor: .tertiarySystemBackground),
        fallbackIconColor: Color = Color(uiColor: .secondaryLabel)
    ) {
        self.brand = brand
        self.borderColor = borderColor
        self.emptyBackgroundColor = emptyBackgroundColor
        self.fallbackIconColor = fallbackIconColor
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(brand.brandAssetName == nil ? emptyBackgroundColor : .white)
            RoundedRectangle(cornerRadius: 5)
                .stroke(borderColor, lineWidth: 1)

            if let assetName = brand.brandAssetName {
                Image(assetName, bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "creditcard")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(fallbackIconColor)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 42, height: 26)
        .accessibilityHidden(true)
    }
}
