import PayabliSDKPayInPaymentFlow
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

    static let allowedMethods: [PayabliPayInPaymentFlowMethodType] = [.card, .ach]
    static let defaultMethod: PayabliPayInPaymentFlowMethodType = .card

    static let cardFieldOrder: [PayabliPayInPaymentFlowField] = [
        .cardholderName,
        .cardNumber,
        .cardExpiration,
        .cardCvv,
        .cardZip
    ]

    static let achFieldOrder: [PayabliPayInPaymentFlowField] = [
        .achHolder,
        .achRouting,
        .achAccount,
        .achAccountType
    ]

    // MARK: - Presentation

    static let labelLayout: PayabliPayInPaymentFlowLabelLayout = .external
    static let showsFieldLabels = true
    static let cardBrandIconPlacement: PayabliPayInPaymentFlowCardBrandIconPlacement = .trailing

    static let formatting = PayabliPayInPaymentFlowFormatting(
        insertsCardNumberSpaces: true,
        masksACHAccountEntry: true
    )

    static let inputSizing = PayabliPayInPaymentFlowInputSizing(
        defaultSize: PayabliPayInPaymentFlowInputSize(height: 52),
        fieldSizes: [
            .cardExpiration: PayabliPayInPaymentFlowInputSize(height: 48),
            .cardCvv: PayabliPayInPaymentFlowInputSize(height: 48)
        ]
    )

    /// Fields whose label is hidden because the placeholder already says it.
    static let fieldsWithHiddenLabels: [PayabliPayInPaymentFlowField] = [
        .cardholderName,
        .cardNumber,
        .cardExpiration,
        .cardCvv,
        .cardZip,
        .achHolder,
        .achRouting,
        .achAccount,
        .achAccountType,
        .firstName,
        .lastName,
        .billingEmail
    ]

    /// Placeholders that match the SDK's own field labels, so hiding a label
    /// loses no information.
    static func labelMatchingPlaceholders(
        for fields: [PayabliPayInPaymentFlowField] = fieldsWithHiddenLabels
    ) -> [PayabliPayInPaymentFlowField: String] {
        Dictionary(uniqueKeysWithValues: fields.map { field in
            (
                field,
                PayabliPayInPaymentFlowLabels.defaultFieldLabels[field] ?? field.rawValue
            )
        })
    }

    // MARK: - Style

    static let style = PayabliPayInPaymentFlowStyle(
        accentColor: .payabliPrimary,
        input: PayabliPayInPaymentFlowInputStyle(
            backgroundColor: Color.payabliBackground,
            borderColor: Color.payabliOutlineVariant.opacity(0.6),
            cornerRadius: 8
        ),
        submitButton: PayabliPayInPaymentFlowSubmitButtonStyle(cornerRadius: 8),
        layout: PayabliPayInPaymentFlowLayoutStyle(
            contentSpacing: 18,
            fieldGroupSpacing: 14,
            pairedFieldSpacing: 12,
            sectionSpacing: 20,
            sectionTitleSpacing: 10
        )
    )

    /// Section-title styling, repeated verbatim on every section in both tabs.
    static let sectionTitleStyle = PayabliPayInPaymentFlowTextStyle(
        font: .headline.weight(.semibold),
        color: .primary
    )
}
