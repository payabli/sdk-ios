import SwiftUI
import PayabliSDKCore

/// Turn-key SwiftUI ACH form. Tokenize or charge a bank account with a single View.
///
/// Two operations, selected at construction time:
/// - `init(customerId:theme:onCompletion:)` — tokenize via
///   `POST /api/TokenStorage/add`.
/// - `init(paymentRequest:customerId:theme:onCompletion:)` — authorize-and-capture
///   via `POST /api/v2/MoneyIn/getpaid`.
///
/// UI, fields, and validation (routing ABA checksum, account length) are
/// identical across both modes (PRD FR-4.1, FR-4.2, FR-4.4). The submit button
/// is disabled until `viewModel.isValid == true`.
///
/// Usage (tokenization):
/// ```swift
/// ACHFormView(customerId: 4440) { token, error in
///     // handle result
/// }
/// ```
///
/// For sheet presentation see `.payabliAchSheet(isPresented:...)`.
@available(iOS 15.0, macOS 12.0, *)
public struct ACHFormView: View {
    @StateObject private var viewModel = ACHFormViewModel()
    private let theme: PayabliTheme
    private let strings: ACHFormStrings
    private let operation: Operation

    @FocusState private var focusedField: ACHFormViewModel.Field?

    /// Tokenize a bank account — submit calls `POST /api/TokenStorage/add`.
    ///
    /// - Parameters:
    ///   - customerId: Payabli customer ID the new method is attached to.
    ///   - theme: Visual theming (colors, corner radius). Defaults to Payabli green.
    ///   - strings: Customizable copy (labels, placeholders, errors,
    ///     button title). Defaults to the English reference copy.
    ///   - onCompletion: Receives the stored-method token on success.
    public init(
        customerId: Int,
        theme: PayabliTheme = .default,
        strings: ACHFormStrings = .default,
        onCompletion: @escaping PayabliTokenizationCompletion
    ) {
        self.theme = theme
        self.strings = strings
        self.operation = .tokenize(customerId: customerId, completion: onCompletion)
    }

    /// Charge a bank account now — submit calls `POST /api/v2/MoneyIn/getpaid`.
    ///
    /// See `init(customerId:theme:strings:onCompletion:)` for the
    /// customization parameters.
    public init(
        paymentRequest: PayabliPaymentRequest,
        customerId: Int,
        theme: PayabliTheme = .default,
        strings: ACHFormStrings = .default,
        onCompletion: @escaping PayabliPaymentCompletion
    ) {
        self.theme = theme
        self.strings = strings
        self.operation = .charge(
            request: paymentRequest,
            customerId: customerId,
            completion: onCompletion
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fieldLabel(strings.holderNameLabel)
                input(
                    $viewModel.holderName,
                    placeholder: strings.holderNamePlaceholder,
                    field: .holderName,
                    keyboardType: .default,
                    accessibilityLabel: strings.holderNameLabel,
                    capitalization: .words,
                    submitLabel: .next,
                    onReturn: { focusedField = .routingNumber },
                    error: viewModel.errorMessage(for: .holderName)
                )

                fieldLabel(strings.routingNumberLabel)
                input(
                    $viewModel.routingNumber,
                    placeholder: strings.routingNumberPlaceholder,
                    field: .routingNumber,
                    keyboardType: .numberPad,
                    accessibilityLabel: strings.routingNumberLabel,
                    error: viewModel.errorMessage(for: .routingNumber)
                )

                fieldLabel(strings.accountNumberLabel)
                input(
                    $viewModel.accountNumber,
                    placeholder: strings.accountNumberPlaceholder,
                    field: .accountNumber,
                    keyboardType: .numberPad,
                    accessibilityLabel: strings.accountNumberLabel,
                    error: viewModel.errorMessage(for: .accountNumber)
                )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel(strings.accountTypeLabel)
                        Picker(strings.accountTypeLabel, selection: $viewModel.accountType) {
                            Text(strings.accountTypeChecking).tag(ACHAccountType.checking)
                            Text(strings.accountTypeSavings).tag(ACHAccountType.savings)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel(strings.accountTypeLabel)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel(strings.holderTypeLabel)
                        Picker(strings.holderTypeLabel, selection: $viewModel.holderType) {
                            Text(strings.holderTypePersonal).tag(ACHHolderType.personal)
                            Text(strings.holderTypeBusiness).tag(ACHHolderType.business)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel(strings.holderTypeLabel)
                    }
                }

                if let lastError = viewModel.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                        .accessibilityLabel("Error: \(lastError)")
                }

                Button(action: submit) {
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
                .accessibilityIdentifier("ach-form.submit")
                .accessibilityLabel(submitTitle)
                .accessibilityHint(
                    viewModel.isValid ? "Double-tap to submit" : "Complete all fields to enable"
                )
            }
            .padding(24)
        }
        .onAppear {
            // Push customization into the @StateObject VM. Done in onAppear
            // because @StateObject can't be initialized from init params.
            viewModel.strings = strings
        }
        .onChange(of: focusedField) { newField in
            for field in ACHFormViewModel.Field.allCases where field != newField {
                if !viewModel.touchedFields.contains(field) && hasAnyContent(for: field) {
                    viewModel.markTouched(field)
                }
            }
        }
        // Auto-advance: routing number complete (9 digits) → account number.
        .onChange(of: viewModel.routingNumber) { newValue in
            guard
                focusedField == .routingNumber,
                newValue.filter(\.isNumber).count >= ACHFormViewModel.routingLength
            else { return }
            focusedField = .accountNumber
        }
    }

    // MARK: - Derived

    private var submitTitle: String {
        switch operation {
        case .tokenize:
            return strings.saveButtonTitle
        case .charge(let request, _, _):
            return PayabliPayIn.shared.formatPayButtonTitle(request: request)
        }
    }

    private func submit() {
        Task { @MainActor in
            switch operation {
            case .tokenize(let customerId, let completion):
                await PayabliPayIn.shared.submitACHTokenization(
                    viewModel,
                    customerId: customerId,
                    completion: completion
                )
            case .charge(let request, let customerId, let completion):
                await PayabliPayIn.shared.submitACHPayment(
                    viewModel,
                    request: request,
                    customerId: customerId,
                    completion: completion
                )
            }
        }
    }

    // MARK: - Atoms

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.caption).foregroundColor(.secondary)
    }

    /// Cross-platform capitalization mode — iOS maps to
    /// `TextInputAutocapitalization`; macOS ignores it (test-only builds).
    enum Capitalization { case none, words }

    @ViewBuilder
    private func input(
        _ binding: Binding<String>,
        placeholder: String,
        field: ACHFormViewModel.Field,
        keyboardType: UIKeyboardType,
        accessibilityLabel: String,
        capitalization: Capitalization = .none,
        submitLabel: SubmitLabel = .next,
        onReturn: @escaping () -> Void = {},
        error: String?
    ) -> some View {
        TextField(placeholder, text: binding)
            #if os(iOS)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(capitalization == .words ? .words : .never)
            .disableAutocorrection(capitalization == .none)
            #endif
            .submitLabel(submitLabel)
            .onSubmit(onReturn)
            .focused($focusedField, equals: field)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("ach-form.\(field)")
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
                        .accessibilityLabel("\(accessibilityLabel) error: \(error)")
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

    // MARK: - Operation

    private enum Operation {
        case tokenize(customerId: Int, completion: PayabliTokenizationCompletion)
        case charge(
            request: PayabliPaymentRequest,
            customerId: Int,
            completion: PayabliPaymentCompletion
        )
    }
}

// MARK: - Sheet modifier

@available(iOS 15.0, macOS 12.0, *)
extension View {
    /// Presents an ACH tokenization sheet bound to `isPresented`.
    public func payabliAchSheet(
        isPresented: Binding<Bool>,
        customerId: Int,
        theme: PayabliTheme = .default,
        strings: ACHFormStrings = .default,
        onCompletion: @escaping PayabliTokenizationCompletion
    ) -> some View {
        modifier(PayabliAchTokenizeSheetModifier(
            isPresented: isPresented,
            customerId: customerId,
            theme: theme,
            strings: strings,
            onCompletion: onCompletion
        ))
    }

    /// Presents an ACH payment sheet bound to `isPresented`.
    public func payabliAchSheet(
        isPresented: Binding<Bool>,
        paymentRequest: PayabliPaymentRequest,
        customerId: Int,
        theme: PayabliTheme = .default,
        strings: ACHFormStrings = .default,
        onCompletion: @escaping PayabliPaymentCompletion
    ) -> some View {
        modifier(PayabliAchChargeSheetModifier(
            isPresented: isPresented,
            paymentRequest: paymentRequest,
            customerId: customerId,
            theme: theme,
            strings: strings,
            onCompletion: onCompletion
        ))
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct PayabliAchTokenizeSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let customerId: Int
    let theme: PayabliTheme
    let strings: ACHFormStrings
    let onCompletion: PayabliTokenizationCompletion

    @State private var didCompleteNonCancel = false

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: $isPresented,
            onDismiss: {
                if !didCompleteNonCancel {
                    onCompletion(nil, PayabliGenericError(
                        code: .userCancelled,
                        reason: "User cancelled"
                    ))
                }
                didCompleteNonCancel = false
            }
        ) {
            VStack(spacing: 0) {
                PayabliSheetHeader(title: strings.sheetTitle, tint: theme.primaryColor) {
                    isPresented = false
                }
                Divider()
                ACHFormView(
                    customerId: customerId,
                    theme: theme,
                    strings: strings
                ) { token, error in
                    didCompleteNonCancel = true
                    onCompletion(token, error)
                    isPresented = false
                }
            }
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct PayabliAchChargeSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let paymentRequest: PayabliPaymentRequest
    let customerId: Int
    let theme: PayabliTheme
    let strings: ACHFormStrings
    let onCompletion: PayabliPaymentCompletion

    @State private var didCompleteNonCancel = false

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: $isPresented,
            onDismiss: {
                if !didCompleteNonCancel {
                    onCompletion(nil, PayabliGenericError(
                        code: .userCancelled,
                        reason: "User cancelled"
                    ))
                }
                didCompleteNonCancel = false
            }
        ) {
            VStack(spacing: 0) {
                PayabliSheetHeader(title: strings.sheetTitle, tint: theme.primaryColor) {
                    isPresented = false
                }
                Divider()
                ACHFormView(
                    paymentRequest: paymentRequest,
                    customerId: customerId,
                    theme: theme,
                    strings: strings
                ) { result, error in
                    didCompleteNonCancel = true
                    onCompletion(result, error)
                    isPresented = false
                }
            }
        }
    }
}

// Compatibility shim for cross-platform (macOS test builds).
#if !os(iOS)
private enum UIKeyboardType { case `default`, numberPad, emailAddress }
#endif
