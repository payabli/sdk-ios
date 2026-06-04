import SwiftUI
import UIKit

public struct PayabliPaymentMethodTextStyle {
    public let font: Font
    public let color: Color

    public init(
        font: Font,
        color: Color
    ) {
        self.font = font
        self.color = color
    }
}

public struct PayabliPaymentMethodInputStyle {
    public let font: Font
    public let uiFont: UIFont?
    public let textColor: Color
    public let placeholderColor: Color
    public let backgroundColor: Color
    public let focusedBackgroundColor: Color?
    public let borderColor: Color
    public let focusedBorderColor: Color?
    public let borderWidth: CGFloat
    public let focusedBorderWidth: CGFloat
    public let cornerRadius: CGFloat
    public let pickerIconColor: Color

    public init(
        font: Font = .body,
        uiFont: UIFont? = nil,
        textColor: Color = .primary,
        placeholderColor: Color = Color(uiColor: .placeholderText),
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
        self.uiFont = uiFont
        self.textColor = textColor
        self.placeholderColor = placeholderColor
        self.backgroundColor = backgroundColor
        self.focusedBackgroundColor = focusedBackgroundColor
        self.borderColor = borderColor
        self.focusedBorderColor = focusedBorderColor
        self.borderWidth = max(0, borderWidth)
        self.focusedBorderWidth = max(0, focusedBorderWidth)
        self.cornerRadius = max(0, cornerRadius)
        self.pickerIconColor = pickerIconColor
    }

    var resolvedUIFont: UIFont {
        if let uiFont {
            return UIFontMetrics(forTextStyle: .body).scaledFont(for: uiFont)
        }
        return UIFont.preferredFont(forTextStyle: .body)
    }
}

public struct PayabliPaymentMethodSubmitButtonStyle {
    public let font: Font
    public let backgroundColor: Color?
    public let foregroundColor: Color
    public let disabledBackgroundColor: Color
    public let disabledForegroundColor: Color
    public let cornerRadius: CGFloat
    public let height: CGFloat
    public let horizontalPadding: CGFloat

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
        self.height = max(PayabliPaymentMethodAccessibility.minimumTouchTarget, height)
        self.horizontalPadding = max(0, horizontalPadding)
    }
}

public struct PayabliPaymentMethodLayoutStyle {
    public private(set) var contentSpacing: CGFloat
    public private(set) var headerSpacing: CGFloat
    public private(set) var fieldGroupSpacing: CGFloat
    public private(set) var pairedFieldSpacing: CGFloat
    public private(set) var labelSpacing: CGFloat
    public private(set) var sectionSpacing: CGFloat
    public private(set) var sectionTitleSpacing: CGFloat

    public var inputVerticalSpacing: CGFloat {
        get { fieldGroupSpacing }
        set { fieldGroupSpacing = max(0, newValue) }
    }

    public var inputHorizontalSpacing: CGFloat {
        get { pairedFieldSpacing }
        set { pairedFieldSpacing = max(0, newValue) }
    }

    public init(
        contentSpacing: CGFloat = 20,
        headerSpacing: CGFloat = 4,
        fieldGroupSpacing: CGFloat = 12,
        pairedFieldSpacing: CGFloat = 12,
        labelSpacing: CGFloat = 7,
        sectionSpacing: CGFloat = 18,
        sectionTitleSpacing: CGFloat = 10
    ) {
        self.contentSpacing = max(0, contentSpacing)
        self.headerSpacing = max(0, headerSpacing)
        self.fieldGroupSpacing = max(0, fieldGroupSpacing)
        self.pairedFieldSpacing = max(0, pairedFieldSpacing)
        self.labelSpacing = max(0, labelSpacing)
        self.sectionSpacing = max(0, sectionSpacing)
        self.sectionTitleSpacing = max(0, sectionTitleSpacing)
    }
}

public struct PayabliPaymentMethodStyle {
    public let accentColor: Color
    public let title: PayabliPaymentMethodTextStyle
    public let subtitle: PayabliPaymentMethodTextStyle
    public let sectionTitle: PayabliPaymentMethodTextStyle
    public let label: PayabliPaymentMethodTextStyle
    public let input: PayabliPaymentMethodInputStyle
    public let submitButton: PayabliPaymentMethodSubmitButtonStyle
    public let error: PayabliPaymentMethodTextStyle
    public let layout: PayabliPaymentMethodLayoutStyle

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
        sectionTitle: PayabliPaymentMethodTextStyle = PayabliPaymentMethodTextStyle(
            font: .subheadline.weight(.semibold),
            color: .primary
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
        self.sectionTitle = sectionTitle
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
