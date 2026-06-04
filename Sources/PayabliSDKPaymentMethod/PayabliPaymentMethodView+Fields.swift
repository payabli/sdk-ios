import PayabliSDKCore
import SwiftUI
import UIKit

extension PayabliPaymentMethodView {
    @ViewBuilder
    func cardFieldView(_ field: PayabliPaymentMethodField) -> some View {
        switch field {
        case .cardholderName:
            textField(
                field,
                text: cardholderNameBinding,
                textContentType: .name,
                autocapitalization: .words,
                sanitize: viewModel.limitCardholderName
            )
        case .cardNumber:
            cardNumberField()
        case .cardExpiration:
            expirationPickerField()
        case .cardCvv:
            secureField(
                field,
                text: cardCvvBinding,
                keyboardType: .numberPad,
                sanitize: viewModel.limitCardCvv
            )
        case .cardZip:
            textField(
                field,
                text: cardZipBinding,
                keyboardType: .numbersAndPunctuation,
                sanitize: viewModel.limitPostalCode
            )
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    func achFieldView(_ field: PayabliPaymentMethodField) -> some View {
        switch field {
        case .achHolder:
            textField(
                field,
                text: achHolderBinding,
                textContentType: .name,
                autocapitalization: .words,
                sanitize: viewModel.limitACHHolderName
            )
        case .achRouting:
            textField(
                field,
                text: achRoutingBinding,
                keyboardType: .numberPad,
                sanitize: viewModel.limitACHRouting
            )
        case .achAccount:
            if configuration.formatting.masksACHAccountEntry {
                secureField(
                    field,
                    text: achAccountBinding,
                    keyboardType: .numberPad,
                    sanitize: viewModel.limitACHAccount
                )
            } else {
                textField(
                    field,
                    text: achAccountBinding,
                    keyboardType: .numberPad,
                    sanitize: viewModel.limitACHAccount
                )
            }
        case .achAccountType:
            pickerField(field, selection: $viewModel.achAccountType, values: PayabliACHAccountType.allCases)
        case .achHolderType:
            pickerField(field, selection: $viewModel.achHolderType, values: PayabliACHHolderType.allCases)
        case .achSecCode:
            pickerField(field, selection: $viewModel.achSecCode, values: PayabliACHSecCode.allCases)
        case .achDevice:
            textField(field, text: $viewModel.achDevice)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    func customerFieldView(_ field: PayabliPaymentMethodField) -> some View {
        switch field {
        case .methodDescription:
            textField(field, text: $viewModel.methodDescription, autocapitalization: .sentences)
        case .firstName:
            textField(
                field,
                text: $viewModel.firstName,
                textContentType: .givenName,
                autocapitalization: .words
            )
        case .lastName:
            textField(
                field,
                text: $viewModel.lastName,
                textContentType: .familyName,
                autocapitalization: .words
            )
        case .customerNumber:
            textField(field, text: $viewModel.customerNumber)
        case .billingEmail:
            textField(field, text: $viewModel.billingEmail, keyboardType: .emailAddress, textContentType: .emailAddress)
        case .billingZip:
            textField(
                field,
                text: billingZipBinding,
                keyboardType: .numbersAndPunctuation,
                sanitize: viewModel.limitPostalCode
            )
        default:
            EmptyView()
        }
    }

    func textField(
        _ field: PayabliPaymentMethodField,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: UITextAutocapitalizationType = .none,
        sanitize: @escaping (String) -> String = { $0 }
    ) -> some View {
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            PayabliPaymentMethodUIKitTextField(
                text: text,
                placeholder: placeholder(for: field),
                field: field,
                focusedField: focusedFieldBinding,
                keyboardType: keyboardType,
                textContentType: textContentType,
                autocapitalization: autocapitalization,
                isSecure: false,
                font: inputUIKitFont,
                textColor: inputUIKitTextColor,
                placeholderColor: inputUIKitPlaceholderColor,
                accessibilityLabel: label,
                sanitize: sanitize
            )
            .padding(.horizontal, inputSize.horizontalPadding)
            .frame(width: inputSize.width)
            .frame(minHeight: inputSize.height)
            .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
            .background(fieldBackground(field))
            .overlay(fieldBorder(field))
            .clipShape(inputShape)
            .privacySensitive()
        }
    }

    func cardNumberField() -> some View {
        let field = PayabliPaymentMethodField.cardNumber
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)
        let text = Binding(
            get: { viewModel.cardNumber },
            set: { viewModel.cardNumber = $0 }
        )

        return fieldRow(
            field,
            errorMessage: viewModel.cardNumberValidationMessage,
            reservedErrorMessage: showsExternalLabel(for: field) ? "Invalid Card Number" : nil
        ) {
            HStack(spacing: 10) {
                if configuration.cardBrandIconPlacement == .leading {
                    cardBrandIcon
                }

                PayabliPaymentMethodUIKitTextField(
                    text: text,
                    placeholder: placeholder(for: field),
                    field: field,
                    focusedField: focusedFieldBinding,
                    keyboardType: .numberPad,
                    textContentType: .creditCardNumber,
                    autocapitalization: .none,
                    isSecure: false,
                    font: inputUIKitFont,
                    textColor: cardNumberUIKitTextColor,
                    placeholderColor: inputUIKitPlaceholderColor,
                    accessibilityLabel: label,
                    accessibilityHint: PayabliPaymentMethodAccessibility.cardNumberHint(
                        brand: viewModel.detectedCardBrand,
                        validationMessage: viewModel.cardNumberValidationMessage
                    ),
                    sanitize: viewModel.formatCardNumber
                )
                .frame(maxWidth: .infinity, minHeight: inputSize.height, alignment: .leading)

                if configuration.cardBrandIconPlacement == .trailing {
                    cardBrandIcon
                }
            }
            .padding(.horizontal, inputSize.horizontalPadding)
            .frame(width: inputSize.width)
            .frame(minHeight: inputSize.height)
            .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
            .background(fieldBackground(field))
            .overlay(fieldBorder(field))
            .clipShape(inputShape)
            .privacySensitive()
        }
    }

    func expirationPickerField() -> some View {
        let field = PayabliPaymentMethodField.cardExpiration
        let label = configuration.labels.label(for: field)
        let placeholder = placeholder(for: field, defaultText: "MM/YY")
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            Button {
                focusedField = nil
                viewModel.ensureExpirationSelection()
                isExpirationPickerPresented = true
            } label: {
                HStack(spacing: 10) {
                    Text(viewModel.hasSelectedExpiration ? viewModel.expirationDisplayText : placeholder)
                        .font(resolvedStyle.input.font)
                        .foregroundStyle(
                            viewModel.hasSelectedExpiration
                                ? resolvedStyle.input.textColor
                                : resolvedStyle.input.placeholderColor
                        )
                    Spacer(minLength: 8)
                    Image(systemName: "calendar")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(resolvedStyle.input.pickerIconColor)
                }
                .padding(.horizontal, inputSize.horizontalPadding)
                .frame(width: inputSize.width)
                .frame(minHeight: inputSize.height)
                .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
                .background(fieldBackground(nil))
                .overlay(fieldBorder(nil))
                .clipShape(inputShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(PayabliPaymentMethodAccessibility.expirationValue(
                displayText: viewModel.expirationDisplayText,
                hasSelectedExpiration: viewModel.hasSelectedExpiration
            ))
            .accessibilityHint(PayabliPaymentMethodAccessibility.expirationHint(format: placeholder))
            .accessibilityIdentifier(PayabliPaymentMethodAccessibility.fieldIdentifier(field))
        }
    }

    var expirationWheelSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(configuration.labels.label(for: .cardExpiration))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button("Done") {
                    isExpirationPickerPresented = false
                }
                .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)

            HStack(spacing: 0) {
                Picker("Month", selection: expirationMonthSelection) {
                    ForEach(1 ... 12, id: \.self) { month in
                        Text(expirationWheelMonthLabel(month))
                            .tag(month)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Picker("Year", selection: expirationYearSelection) {
                    ForEach(expirationYears, id: \.self) { year in
                        Text(String(year))
                            .tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 210)
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .onAppear {
            viewModel.ensureExpirationSelection()
        }
    }

    var cardBrandIcon: some View {
        let brand = viewModel.detectedCardBrand

        return ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(brand.brandAssetName == nil ? Color(uiColor: .tertiarySystemBackground) : .white)
            RoundedRectangle(cornerRadius: 5)
                .stroke(resolvedStyle.input.borderColor.opacity(0.65), lineWidth: 1)

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
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 42, height: 26)
        .accessibilityHidden(true)
    }

    func secureField(
        _ field: PayabliPaymentMethodField,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        sanitize: @escaping (String) -> String = { $0 }
    ) -> some View {
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            PayabliPaymentMethodUIKitTextField(
                text: text,
                placeholder: placeholder(for: field),
                field: field,
                focusedField: focusedFieldBinding,
                keyboardType: keyboardType,
                autocapitalization: .none,
                isSecure: true,
                font: inputUIKitFont,
                textColor: inputUIKitTextColor,
                placeholderColor: inputUIKitPlaceholderColor,
                accessibilityLabel: label,
                sanitize: sanitize
            )
            .padding(.horizontal, inputSize.horizontalPadding)
            .frame(width: inputSize.width)
            .frame(minHeight: inputSize.height)
            .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
            .background(fieldBackground(field))
            .overlay(fieldBorder(field))
            .clipShape(inputShape)
            .privacySensitive()
        }
    }

    func pickerField<Value>(
        _ field: PayabliPaymentMethodField,
        selection: Binding<Value>,
        values: [Value]
    ) -> some View where Value: RawRepresentable & Identifiable & Hashable, Value.RawValue == String {
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            Menu {
                ForEach(values) { value in
                    Button {
                        selection.wrappedValue = value
                    } label: {
                        if selection.wrappedValue == value {
                            Label(value.rawValue, systemImage: "checkmark")
                        } else {
                            Text(value.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selection.wrappedValue.rawValue)
                        .font(resolvedStyle.input.font)
                        .foregroundStyle(resolvedStyle.input.textColor)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(resolvedStyle.input.pickerIconColor)
                }
                .padding(.horizontal, inputSize.horizontalPadding)
                .frame(width: inputSize.width)
                .frame(minHeight: inputSize.height)
                .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
                .background(fieldBackground(nil))
                .overlay(fieldBorder(nil))
                .clipShape(inputShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(selection.wrappedValue.rawValue)
            .accessibilityHint(PayabliPaymentMethodAccessibility.pickerHint(label: label))
            .accessibilityIdentifier(PayabliPaymentMethodAccessibility.fieldIdentifier(field))
        }
    }

    func fieldRow(
        _ field: PayabliPaymentMethodField,
        errorMessage: String? = nil,
        reservedErrorMessage: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let inputSize = configuration.inputSizing.size(for: field)

        return VStack(alignment: .leading, spacing: resolvedStyle.layout.labelSpacing) {
            if showsExternalLabel(for: field) {
                Text(configuration.labels.label(for: field))
                    .font(resolvedStyle.label.font)
                    .foregroundStyle(resolvedStyle.label.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()

            if let errorMessage {
                fieldErrorText(errorMessage, for: field)
            } else if let reservedErrorMessage {
                fieldErrorText(reservedErrorMessage, for: field)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .frame(width: inputSize.width)
        .frame(maxWidth: inputSize.width == nil ? .infinity : nil, alignment: .leading)
    }
}
