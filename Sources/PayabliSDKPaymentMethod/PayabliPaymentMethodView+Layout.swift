import PayabliSDKCore
import SwiftUI
import UIKit

extension PayabliPaymentMethodView {
    func fieldSection(_ section: PayabliPaymentMethodFieldSection) -> some View {
        let groups = fieldGroups(for: section.fields)

        return VStack(alignment: .leading, spacing: section.title == nil ? 0 : resolvedStyle.layout.sectionTitleSpacing) {
            if let title = section.title {
                Text(title)
                    .font(resolvedStyle.sectionTitle.font)
                    .foregroundStyle(resolvedStyle.sectionTitle.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    fieldGroup(
                        group,
                        horizontalSpacing: inputHorizontalSpacing(in: section)
                    )

                    if index < groups.count - 1 {
                        Color.clear
                            .frame(height: verticalSpacing(after: group, in: section))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func fieldGroup(
        _ fields: [PayabliPaymentMethodField],
        horizontalSpacing: CGFloat
    ) -> some View {
        if fields.count == 2 {
            HStack(alignment: .top, spacing: horizontalSpacing) {
                ForEach(fields) { field in
                    fieldView(field)
                }
            }
        } else if let field = fields.first {
            fieldView(field)
        }
    }

    func inputVerticalSpacing(in section: PayabliPaymentMethodFieldSection) -> CGFloat {
        section.inputVerticalSpacing ?? resolvedStyle.layout.inputVerticalSpacing
    }

    func inputHorizontalSpacing(in section: PayabliPaymentMethodFieldSection) -> CGFloat {
        section.inputHorizontalSpacing ?? resolvedStyle.layout.inputHorizontalSpacing
    }

    func verticalSpacing(
        after fields: [PayabliPaymentMethodField],
        in section: PayabliPaymentMethodFieldSection
    ) -> CGFloat {
        for field in fields.reversed() {
            if let spacing = section.fieldVerticalSpacings[field] {
                return spacing
            }
        }

        return inputVerticalSpacing(in: section)
    }

    func shouldPair(
        _ first: PayabliPaymentMethodField,
        _ second: PayabliPaymentMethodField
    ) -> Bool {
        guard !dynamicTypeSize.isAccessibilitySize else {
            return false
        }

        switch (first, second) {
        case (.cardExpiration, .cardCvv),
             (.cardCvv, .cardExpiration),
             (.firstName, .lastName),
             (.lastName, .firstName):
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    func fieldView(_ field: PayabliPaymentMethodField) -> some View {
        switch field {
        case .cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip:
            cardFieldView(field)
        case .achHolder, .achRouting, .achAccount, .achAccountType, .achHolderType, .achSecCode, .achDevice:
            achFieldView(field)
        case .methodDescription, .firstName, .lastName, .customerNumber, .billingEmail, .billingZip:
            customerFieldView(field)
        }
    }

    var cardholderNameBinding: Binding<String> {
        Binding(
            get: { viewModel.cardholderName },
            set: { viewModel.cardholderName = $0 }
        )
    }

    var focusedFieldBinding: Binding<PayabliPaymentMethodField?> {
        Binding(
            get: { focusedField },
            set: { focusedField = $0 }
        )
    }

    var cardCvvBinding: Binding<String> {
        Binding(
            get: { viewModel.cardCvv },
            set: { viewModel.cardCvv = $0 }
        )
    }

    var cardZipBinding: Binding<String> {
        Binding(
            get: { viewModel.cardZip },
            set: { viewModel.cardZip = $0 }
        )
    }

    var achHolderBinding: Binding<String> {
        Binding(
            get: { viewModel.achHolder },
            set: { viewModel.achHolder = $0 }
        )
    }

    var achRoutingBinding: Binding<String> {
        Binding(
            get: { viewModel.achRouting },
            set: { viewModel.achRouting = $0 }
        )
    }

    var achAccountBinding: Binding<String> {
        Binding(
            get: { viewModel.achAccount },
            set: { viewModel.achAccount = $0 }
        )
    }

    var billingZipBinding: Binding<String> {
        Binding(
            get: { viewModel.billingZip },
            set: { viewModel.billingZip = $0 }
        )
    }
}
