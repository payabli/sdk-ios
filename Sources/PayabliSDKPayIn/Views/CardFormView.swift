import SwiftUI
import PayabliSDKCore

/// SwiftUI form for card tokenization / card payment.
///
/// On-blur validation: the view marks each field "touched" when focus moves
/// away from it, so error messages don't appear until the user has visited
/// the field (PRD FR-4.1, FR-4.2).
///
/// The submit button is disabled until `viewModel.isValid == true` (FR-4.4).
@available(iOS 15.0, macOS 12.0, *)
public struct CardFormView: View {
    @ObservedObject var viewModel: CardFormViewModel
    let theme: PayabliTheme
    /// Submit-button label. Supplied by the facade so tokenization reads
    /// "Save Payment Method" and getpaid reads "Pay $XX.XX" (FR-4.4).
    let submitTitle: String
    let onSubmit: () -> Void

    @FocusState private var focusedField: CardFormViewModel.Field?

    public init(
        viewModel: CardFormViewModel,
        theme: PayabliTheme,
        submitTitle: String,
        onSubmit: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.theme = theme
        self.submitTitle = submitTitle
        self.onSubmit = onSubmit
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fieldLabel("Card holder name")
                input(
                    $viewModel.holderName,
                    placeholder: "Jane Doe",
                    field: .holderName,
                    error: viewModel.errorMessage(for: .holderName)
                )

                fieldLabel("Card number")
                input(
                    $viewModel.cardNumber,
                    placeholder: "4242 4242 4242 4242",
                    field: .cardNumber,
                    keyboardType: .numberPad,
                    error: viewModel.errorMessage(for: .cardNumber),
                    trailingView: AnyView(brandBadge)
                )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Expiration")
                        ExpirationPickerView(
                            month: $viewModel.expirationMonth,
                            year: $viewModel.expirationYear,
                            cornerRadius: theme.cornerRadius
                        )
                        .onChange(of: viewModel.expirationMonth) { _ in
                            viewModel.markTouched(.expiration)
                        }
                        if let err = viewModel.errorMessage(for: .expiration) {
                            errorLabel(err)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("CVV")
                        input(
                            $viewModel.cvv,
                            placeholder: "123",
                            field: .cvv,
                            keyboardType: .numberPad,
                            error: viewModel.errorMessage(for: .cvv)
                        )
                    }
                }

                fieldLabel("ZIP code")
                input(
                    $viewModel.zip,
                    placeholder: "90210",
                    field: .zip,
                    keyboardType: .numberPad,
                    error: viewModel.errorMessage(for: .zip)
                )

                if let lastError = viewModel.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }

                Button(action: onSubmit) {
                    HStack {
                        if viewModel.isSubmitting {
                            ProgressView().progressViewStyle(.circular)
                        }
                        Text(submitTitle)
                            .bold()
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .disabled(!viewModel.isValid || viewModel.isSubmitting)
                .buttonStyle(.borderedProminent)
                .tint(theme.primaryColor)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .onChange(of: focusedField) { newField in
            // When focus leaves a field, mark it touched (on-blur validation).
            for field in CardFormViewModel.Field.allCases where field != newField {
                if !viewModel.touchedFields.contains(field) && hasAnyContent(for: field) {
                    viewModel.markTouched(field)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func errorLabel(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.red)
    }

    @ViewBuilder
    private func input(
        _ binding: Binding<String>,
        placeholder: String,
        field: CardFormViewModel.Field,
        keyboardType: UIKeyboardType = .default,
        error: String?,
        trailingView: AnyView? = nil
    ) -> some View {
        HStack {
            TextField(placeholder, text: binding)
                #if os(iOS)
                .keyboardType(keyboardType)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                #endif
                .focused($focusedField, equals: field)
            if let trailingView {
                trailingView
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .stroke(error == nil ? Color.gray.opacity(0.3) : Color.red, lineWidth: 1)
        )
        .overlay(alignment: .bottomLeading) {
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.top, 4)
                    .offset(y: 30)
            }
        }
        .padding(.bottom, error == nil ? 0 : 20)
    }

    @ViewBuilder
    private var brandBadge: some View {
        CardBrandBadge(brand: viewModel.cardBrand)
    }

    private func hasAnyContent(for field: CardFormViewModel.Field) -> Bool {
        switch field {
        case .holderName: return !viewModel.holderName.isEmpty
        case .cardNumber: return !viewModel.cardNumber.isEmpty
        case .expiration: return true
        case .cvv: return !viewModel.cvv.isEmpty
        case .zip: return !viewModel.zip.isEmpty
        }
    }
}

// Compatibility shim for cross-platform (macOS test builds).
#if !os(iOS)
private enum UIKeyboardType { case `default`, numberPad, emailAddress }
#endif
