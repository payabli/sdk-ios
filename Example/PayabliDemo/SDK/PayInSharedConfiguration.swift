import PayabliSDKPayIn
import SwiftUI

/// PayIn configuration shared by the stored-method and capture tabs.
///
/// Everything here was byte-identical in both views before it moved, so a
/// change had to be made twice to keep them consistent. Genuinely per-tab
/// things stay in their view: section decomposition, labels, sheet titles, and
/// the capture-only payment summary.
///
/// The Configuration screen reads these same values, so what it displays cannot
/// drift from what the forms actually use.
enum PayInSharedConfiguration {
    // MARK: - Methods

    static let allowedMethods: [PayabliPayInMethodType] = [.card, .bankAccount]
    static let defaultMethod: PayabliPayInMethodType = .card

    static let cardFieldOrder: [PayabliPayInField] = [
        .cardholderName,
        .cardNumber,
        .cardExpiration,
        .cardCvv,
        .cardZip
    ]

    static let bankFieldOrder: [PayabliPayInField] = [
        .accountHolder,
        .routingNumber,
        .accountNumber,
        .accountType
    ]

    // MARK: - Presentation

    static let labelLayout: PayabliPayInLabelLayout = .external
    static let showsFieldLabels = true
    static let cardBrandIconPlacement: PayabliPayInCardBrandIconPlacement = .trailing

    static let formatting = PayabliPayInFormatting(
        insertsCardNumberSpaces: true,
        masksAccountNumber: true
    )

    static let inputSizing = PayabliPayInInputSizing(
        defaultSize: PayabliPayInInputSize(height: 52),
        fieldSizes: [
            .cardExpiration: PayabliPayInInputSize(height: 48),
            .cardCvv: PayabliPayInInputSize(height: 48)
        ]
    )

    /// Fields whose label is hidden because the placeholder already says it.
    static let fieldsWithHiddenLabels: [PayabliPayInField] = [
        .cardholderName,
        .cardNumber,
        .cardExpiration,
        .cardCvv,
        .cardZip,
        .accountHolder,
        .routingNumber,
        .accountNumber,
        .accountType,
        .firstName,
        .lastName,
        .billingEmail
    ]

    /// Placeholders that match the SDK's own field labels, so hiding a label
    /// loses no information.
    static func labelMatchingPlaceholders(
        for fields: [PayabliPayInField] = fieldsWithHiddenLabels
    ) -> [PayabliPayInField: String] {
        Dictionary(uniqueKeysWithValues: fields.map { field in
            (
                field,
                PayabliPayInLabels.defaultFieldLabels[field] ?? field.rawValue
            )
        })
    }

    // MARK: - Style

    static let style = PayabliPayInStyle(
        accentColor: .payabliPrimary,
        input: PayabliPayInInputStyle(
            backgroundColor: Color.payabliBackground,
            borderColor: Color.payabliOutlineVariant.opacity(0.6),
            cornerRadius: 8
        ),
        submitButton: PayabliPayInSubmitButtonStyle(cornerRadius: 8),
        layout: PayabliPayInLayoutStyle(
            contentSpacing: 18,
            fieldGroupSpacing: 14,
            pairedFieldSpacing: 12,
            sectionSpacing: 20,
            sectionTitleSpacing: 10
        )
    )

    /// Section-title styling, repeated verbatim on every section in both tabs.
    static let sectionTitleStyle = PayabliPayInTextStyle(
        font: .headline.weight(.semibold),
        color: .primary
    )
}
