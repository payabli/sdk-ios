import SwiftUI
import UIKit

public struct PayabliPaymentMethodTextStyle {
    public var font: Font
    public var color: Color

    public init(
        font: Font,
        color: Color
    ) {
        self.font = font
        self.color = color
    }
}

public struct PayabliPaymentMethodInputStyle {
    public var font: Font
    public var textColor: Color
    public var backgroundColor: Color
    public var focusedBackgroundColor: Color?
    public var borderColor: Color
    public var focusedBorderColor: Color?
    public var borderWidth: CGFloat
    public var focusedBorderWidth: CGFloat
    public var cornerRadius: CGFloat
    public var pickerIconColor: Color

    public init(
        font: Font = .body,
        textColor: Color = .primary,
        backgroundColor: Color = Color(uiColor: .secondarySystemBackground),
        focusedBackgroundColor: Color? = nil,
        borderColor: Color = Color(uiColor: .separator).opacity(0.45),
        focusedBorderColor: Color? = nil,
        borderWidth: CGFloat = 1,
        focusedBorderWidth: CGFloat = 1.5,
        cornerRadius: CGFloat = 8,
        pickerIconColor: Color = .secondary
    ) {
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.focusedBackgroundColor = focusedBackgroundColor
        self.borderColor = borderColor
        self.focusedBorderColor = focusedBorderColor
        self.borderWidth = max(0, borderWidth)
        self.focusedBorderWidth = max(0, focusedBorderWidth)
        self.cornerRadius = max(0, cornerRadius)
        self.pickerIconColor = pickerIconColor
    }
}

public struct PayabliPaymentMethodSubmitButtonStyle {
    public var font: Font
    public var backgroundColor: Color?
    public var foregroundColor: Color
    public var disabledBackgroundColor: Color
    public var disabledForegroundColor: Color
    public var cornerRadius: CGFloat
    public var height: CGFloat
    public var horizontalPadding: CGFloat

    public init(
        font: Font = .body.weight(.semibold),
        backgroundColor: Color? = nil,
        foregroundColor: Color = .white,
        disabledBackgroundColor: Color = Color(uiColor: .systemGray5),
        disabledForegroundColor: Color = Color(uiColor: .secondaryLabel),
        cornerRadius: CGFloat = 8,
        height: CGFloat = 52,
        horizontalPadding: CGFloat = 16
    ) {
        self.font = font
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.disabledBackgroundColor = disabledBackgroundColor
        self.disabledForegroundColor = disabledForegroundColor
        self.cornerRadius = max(0, cornerRadius)
        self.height = max(36, height)
        self.horizontalPadding = max(0, horizontalPadding)
    }
}

public struct PayabliPaymentMethodLayoutStyle {
    public var contentSpacing: CGFloat
    public var headerSpacing: CGFloat
    public var fieldGroupSpacing: CGFloat
    public var pairedFieldSpacing: CGFloat
    public var labelSpacing: CGFloat

    public init(
        contentSpacing: CGFloat = 20,
        headerSpacing: CGFloat = 4,
        fieldGroupSpacing: CGFloat = 12,
        pairedFieldSpacing: CGFloat = 12,
        labelSpacing: CGFloat = 7
    ) {
        self.contentSpacing = max(0, contentSpacing)
        self.headerSpacing = max(0, headerSpacing)
        self.fieldGroupSpacing = max(0, fieldGroupSpacing)
        self.pairedFieldSpacing = max(0, pairedFieldSpacing)
        self.labelSpacing = max(0, labelSpacing)
    }
}

public struct PayabliPaymentMethodStyle {
    public var accentColor: Color
    public var title: PayabliPaymentMethodTextStyle
    public var subtitle: PayabliPaymentMethodTextStyle
    public var label: PayabliPaymentMethodTextStyle
    public var input: PayabliPaymentMethodInputStyle
    public var submitButton: PayabliPaymentMethodSubmitButtonStyle
    public var error: PayabliPaymentMethodTextStyle
    public var layout: PayabliPaymentMethodLayoutStyle

    public init(
        accentColor: Color = .accentColor,
        title: PayabliPaymentMethodTextStyle = PayabliPaymentMethodTextStyle(
            font: .title3.weight(.semibold),
            color: .primary
        ),
        subtitle: PayabliPaymentMethodTextStyle = PayabliPaymentMethodTextStyle(
            font: .subheadline,
            color: .secondary
        ),
        label: PayabliPaymentMethodTextStyle = PayabliPaymentMethodTextStyle(
            font: .footnote.weight(.medium),
            color: Color(uiColor: .secondaryLabel)
        ),
        input: PayabliPaymentMethodInputStyle = PayabliPaymentMethodInputStyle(),
        submitButton: PayabliPaymentMethodSubmitButtonStyle = PayabliPaymentMethodSubmitButtonStyle(),
        error: PayabliPaymentMethodTextStyle = PayabliPaymentMethodTextStyle(
            font: .footnote,
            color: .red
        ),
        layout: PayabliPaymentMethodLayoutStyle = PayabliPaymentMethodLayoutStyle()
    ) {
        self.accentColor = accentColor
        self.title = title
        self.subtitle = subtitle
        self.label = label
        self.input = input
        self.submitButton = submitButton
        self.error = error
        self.layout = layout
    }

    public static let `default` = PayabliPaymentMethodStyle()
}

private struct PayabliPaymentMethodStyleKey: EnvironmentKey {
    static let defaultValue = PayabliPaymentMethodStyle.default
}

public extension EnvironmentValues {
    var payabliPaymentMethodStyle: PayabliPaymentMethodStyle {
        get { self[PayabliPaymentMethodStyleKey.self] }
        set { self[PayabliPaymentMethodStyleKey.self] = newValue }
    }
}

public extension View {
    func payabliPaymentMethodStyle(_ style: PayabliPaymentMethodStyle) -> some View {
        environment(\.payabliPaymentMethodStyle, style)
    }
}
