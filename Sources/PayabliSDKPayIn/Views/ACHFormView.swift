import SwiftUI
import PayabliSDKCore

/// SwiftUI form for ACH tokenization / ACH payment.
@available(iOS 15.0, macOS 12.0, *)
public struct ACHFormView: View {
    @ObservedObject var viewModel: ACHFormViewModel
    let theme: PayabliTheme
    let submitTitle: String
    let onSubmit: () -> Void

    @FocusState private var focusedField: ACHFormViewModel.Field?

    public init(
        viewModel: ACHFormViewModel,
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
                label("Account holder name")
                input(
                    $viewModel.holderName,
                    placeholder: "Jane Doe",
                    field: .holderName,
                    error: viewModel.errorMessage(for: .holderName)
                )

                label("Routing number")
                input(
                    $viewModel.routingNumber,
                    placeholder: "021000021",
                    field: .routingNumber,
                    error: viewModel.errorMessage(for: .routingNumber)
                )

                label("Account number")
                input(
                    $viewModel.accountNumber,
                    placeholder: "••••••",
                    field: .accountNumber,
                    error: viewModel.errorMessage(for: .accountNumber)
                )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        label("Account type")
                        Picker("Account type", selection: $viewModel.accountType) {
                            Text("Checking").tag(ACHAccountType.checking)
                            Text("Savings").tag(ACHAccountType.savings)
                        }
                        .pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        label("Holder type")
                        Picker("Holder type", selection: $viewModel.holderType) {
                            Text("Personal").tag(ACHHolderType.personal)
                            Text("Business").tag(ACHHolderType.business)
                        }
                        .pickerStyle(.segmented)
                    }
                }

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
                        Text(submitTitle).bold()
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
            for field in ACHFormViewModel.Field.allCases where field != newField {
                if !viewModel.touchedFields.contains(field) && hasAnyContent(for: field) {
                    viewModel.markTouched(field)
                }
            }
        }
    }

    @ViewBuilder
    private func label(_ text: String) -> some View {
        Text(text).font(.caption).foregroundColor(.secondary)
    }

    @ViewBuilder
    private func input(
        _ binding: Binding<String>,
        placeholder: String,
        field: ACHFormViewModel.Field,
        error: String?
    ) -> some View {
        TextField(placeholder, text: binding)
            #if os(iOS)
            .keyboardType(.numberPad)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            #endif
            .focused($focusedField, equals: field)
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
                        .offset(y: 30)
                }
            }
            .padding(.bottom, error == nil ? 0 : 20)
    }

    private func hasAnyContent(for field: ACHFormViewModel.Field) -> Bool {
        switch field {
        case .holderName: return !viewModel.holderName.isEmpty
        case .routingNumber: return !viewModel.routingNumber.isEmpty
        case .accountNumber: return !viewModel.accountNumber.isEmpty
        }
    }
}
