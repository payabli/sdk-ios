import SwiftUI
import PayabliSDKCore

/// Turn-key SwiftUI card form. Tokenize or charge a card with a single View.
///
/// Two operations, selected at construction time:
/// - `init(customerId:theme:onCompletion:)` — tokenize via
///   `POST /api/TokenStorage/add`, returns the stored-method token.
/// - `init(paymentRequest:customerId:theme:onCompletion:)` — authorize-and-capture
///   via `POST /api/v2/MoneyIn/getpaid`, returns a `PayabliTransactionResult`.
///
/// Visual style: two grouped panels — "Cardholder details" (name, ZIP) and
/// "Card information" (number, MM/YY, CVC) — with floating labels, inline
/// expiration formatting, and brand-aware trailing badges (PRD FR-4.1,
/// FR-4.2, FR-4.4).
///
/// Usage (tokenization):
/// ```swift
/// CardFormView(customerId: 4440) { token, error in
///     // handle result
/// }
/// ```
///
/// For sheet presentation see `.payabliCardSheet(isPresented:...)`.
@available(iOS 15.0, macOS 12.0, *)
public struct CardFormView: View {
    @StateObject private var viewModel = CardFormViewModel()
    private let theme: PayabliTheme
    private let strings: CardFormStrings
    private let allowedBrands: PayabliCardBrand
    private let operation: Operation

    @FocusState private var focusedField: CardFormViewModel.Field?

    /// Tokenize a card — submit calls `POST /api/TokenStorage/add`.
    ///
    /// - Parameters:
    ///   - customerId: Payabli customer ID the new method is attached to.
    ///   - theme: Visual theming (colors, corner radius). Defaults to Payabli green.
    ///   - strings: Customizable copy (labels, errors, button title). Defaults
    ///     to the English reference copy.
    ///   - allowedBrands: Card networks the form will accept. Defaults to
    ///     all four (Visa, Mastercard, Amex, Discover).
    ///   - onCompletion: Receives the stored-method token on success.
    public init(
        customerId: Int,
        theme: PayabliTheme = .default,
        strings: CardFormStrings = .default,
        allowedBrands: PayabliCardBrand = .all,
        onCompletion: @escaping PayabliTokenizationCompletion
    ) {
        self.theme = theme
        self.strings = strings
        self.allowedBrands = allowedBrands
        self.operation = .tokenize(customerId: customerId, completion: onCompletion)
    }

    /// Charge a card now — submit calls `POST /api/v2/MoneyIn/getpaid`.
    ///
    /// See `init(customerId:theme:strings:allowedBrands:onCompletion:)` for
    /// the customization parameters.
    public init(
        paymentRequest: PayabliPaymentRequest,
        customerId: Int,
        theme: PayabliTheme = .default,
        strings: CardFormStrings = .default,
        allowedBrands: PayabliCardBrand = .all,
        onCompletion: @escaping PayabliPaymentCompletion
    ) {
        self.theme = theme
        self.strings = strings
        self.allowedBrands = allowedBrands
        self.operation = .charge(
            request: paymentRequest,
            customerId: customerId,
            completion: onCompletion
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cardPanel

                if let lastError = viewModel.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .accessibilityLabel("Error: \(lastError)")
                }

                submitButton
            }
            .padding(24)
        }
        .onAppear {
            // Push customization into the @StateObject VM. Done in onAppear
            // because @StateObject can't be initialized from init params.
            viewModel.strings = strings
            viewModel.allowedBrands = allowedBrands
        }
        .onChange(of: focusedField) { newField in
            for field in CardFormViewModel.Field.allCases where field != newField {
                if !viewModel.touchedFields.contains(field) && hasAnyContent(for: field) {
                    viewModel.markTouched(field)
                }
            }
        }
        // Auto-advance: PAN complete → expiration.
        .onChange(of: viewModel.cardNumber) { newValue in
            guard
                focusedField == .cardNumber,
                let trigger = PaymentValidators.autoAdvanceDigits(for: viewModel.cardBrand),
                newValue.filter(\.isNumber).count >= trigger
            else { return }
            focusedField = .expiration
        }
        // Auto-advance: expiration (4 digits) → CVV.
        .onChange(of: viewModel.expirationText) { newValue in
            guard
                focusedField == .expiration,
                newValue.filter(\.isNumber).count == 4
            else { return }
            focusedField = .cvv
        }
        // Auto-advance: CVV complete → ZIP.
        .onChange(of: viewModel.cvv) { newValue in
            guard
                focusedField == .cvv,
                newValue.count == PaymentValidators.cvvLength(for: viewModel.cardBrand)
            else { return }
            focusedField = .zip
        }
    }

    // MARK: - Input bindings with view-layer capping
    //
    // SwiftUI's `TextField` has a known race when a `@Published` didSet
    // synchronously re-writes the binding to a shorter value mid-edit: the
    // TextField can briefly render the over-cap intermediate string before
    // re-syncing, and on some iOS minor versions it drifts from the binding
    // entirely. Capping at the binding layer — so the VM never receives an
    // oversized write in the first place — makes the display stable. The
    // VM's own didSet stays as a defensive second layer for programmatic
    // writes (tests, external code).

    private var expirationFieldBinding: Binding<String> {
        Binding(
            get: { viewModel.expirationText },
            set: { newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(4))
                let formatted: String
                switch digits.count {
                case 0, 1, 2:
                    formatted = String(digits)
                default:
                    let mm = digits.prefix(2)
                    let yy = digits.dropFirst(2)
                    formatted = "\(mm) / \(yy)"
                }
                viewModel.expirationText = formatted
            }
        )
    }

    private var cvvFieldBinding: Binding<String> {
        Binding(
            get: { viewModel.cvv },
            set: { newValue in
                let maxLength = PaymentValidators.cvvLength(for: viewModel.cardBrand)
                viewModel.cvv = String(newValue.filter(\.isNumber).prefix(maxLength))
            }
        )
    }

    // MARK: - Panel
    //
    // Single rounded container with three rows, per design:
    //   [ Card holder name                    ]
    //   [ Card number                  [brand] ]
    //   [ MM / YY | CVC | ZIP                 ]

    private var cardPanel: some View {
        panel {
            row {
                floatingField(
                    label: strings.holderNameLabel,
                    text: $viewModel.holderName,
                    field: .holderName,
                    keyboardType: .default,
                    capitalization: .words,
                    submitLabel: .next,
                    onReturn: { focusedField = .cardNumber },
                    accessibilityLabel: strings.holderNameLabel,
                    error: viewModel.errorMessage(for: .holderName)
                )
            }
            Divider()
            row {
                floatingCardNumberField(
                    label: strings.cardNumberLabel,
                    accessibilityLabel: strings.cardNumberLabel,
                    error: viewModel.errorMessage(for: .cardNumber),
                    trailing: AnyView(cardBrandTrailing)
                )
            }
            Divider()
            HStack(spacing: 0) {
                row {
                    floatingField(
                        label: strings.expirationLabel,
                        text: expirationFieldBinding,
                        field: .expiration,
                        keyboardType: .numberPad,
                        accessibilityLabel: strings.expirationLabel,
                        error: viewModel.errorMessage(for: .expiration),
                        monospaced: true,
                        contentType: .creditCardExpiration
                    )
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 44)

                row {
                    floatingField(
                        label: strings.cvcLabel,
                        text: cvvFieldBinding,
                        field: .cvv,
                        keyboardType: .numberPad,
                        accessibilityLabel: strings.cvcLabel,
                        error: viewModel.errorMessage(for: .cvv),
                        monospaced: true,
                        contentType: .creditCardSecurityCode
                    )
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 44)

                row {
                    floatingField(
                        label: strings.zipLabel,
                        text: $viewModel.zip,
                        field: .zip,
                        keyboardType: .numberPad,
                        submitLabel: .go,
                        onReturn: {
                            focusedField = nil
                            if viewModel.isValid && !viewModel.isSubmitting { submit() }
                        },
                        accessibilityLabel: strings.zipLabel,
                        error: viewModel.errorMessage(for: .zip)
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
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
        .accessibilityIdentifier("card-form.submit")
        .accessibilityLabel(submitTitle)
        .accessibilityHint(
            viewModel.isValid ? "Double-tap to submit" : "Complete all fields to enable"
        )
    }

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
                await PayabliPayIn.shared.submitCardTokenization(
                    viewModel,
                    customerId: customerId,
                    completion: completion
                )
            case .charge(let request, let customerId, let completion):
                await PayabliPayIn.shared.submitCardPayment(
                    viewModel,
                    request: request,
                    customerId: customerId,
                    completion: completion
                )
            }
        }
    }

    // MARK: - Atoms

    /// Grouped panel — rounded-rect border wrapping rows separated by Dividers.
    @ViewBuilder
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }

    /// A single row inside a panel — controls vertical padding and height.
    @ViewBuilder
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 56)
    }

    /// Cross-platform capitalization mode.
    enum Capitalization { case none, words }

    /// Optional content-type hint for OS-level autofill. Maps to
    /// `UITextContentType` on iOS; no-op on macOS.
    enum TextContentTypeOption {
        case none
        case creditCardNumber
        case creditCardExpiration   // iOS 17+
        case creditCardSecurityCode // iOS 17+
    }

    /// Generic floating-label chrome — the rounded label that floats up,
    /// the trailing slot, the inline error overlay. Takes whatever inner
    /// `field` view you give it (`TextField`, `PayabliCardNumberField`, …).
    /// `field` is responsible for its own focus / keyboard / accessibility
    /// configuration.
    @ViewBuilder
    private func floatingFieldChrome<Field: View>(
        label: String,
        isActive: Bool,
        isFocused: Bool,
        accessibilityLabel: String,
        error: String?,
        trailing: AnyView? = nil,
        onTap: @escaping () -> Void = {},
        @ViewBuilder field: () -> Field
    ) -> some View {
        let labelColor: Color = error != nil
            ? .red
            : (isFocused ? theme.primaryColor : .secondary)

        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Text(label)
                    .foregroundColor(labelColor)
                    .font(isActive ? .caption : .body)
                    .offset(y: isActive ? -10 : 0)

                field()
                    .offset(y: isActive ? 8 : 0)
            }
            .animation(.easeInOut(duration: 0.15), value: isActive)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            if let trailing { trailing }
        }
        .overlay(alignment: .bottomLeading) {
            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(.leading, 2)
                    .offset(y: 18)
                    .accessibilityLabel("\(accessibilityLabel) error: \(error)")
            }
        }
        .padding(.bottom, error == nil ? 0 : 12)
    }

    /// Floating-label text field — the standard SwiftUI path used by every
    /// row except the PAN (which uses `PayabliCardNumberField` for native
    /// caret handling and credit-card autofill).
    @ViewBuilder
    private func floatingField(
        label: String,
        text: Binding<String>,
        field: CardFormViewModel.Field,
        keyboardType: UIKeyboardType,
        capitalization: Capitalization = .none,
        submitLabel: SubmitLabel = .next,
        onReturn: @escaping () -> Void = {},
        accessibilityLabel: String,
        error: String?,
        trailing: AnyView? = nil,
        monospaced: Bool = false,
        contentType: TextContentTypeOption = .none
    ) -> some View {
        let isActive = focusedField == field || !text.wrappedValue.isEmpty

        floatingFieldChrome(
            label: label,
            isActive: isActive,
            isFocused: focusedField == field,
            accessibilityLabel: accessibilityLabel,
            error: error,
            trailing: trailing,
            onTap: { focusedField = field }
        ) {
            TextField("", text: text)
                #if os(iOS)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(capitalization == .words ? .words : .never)
                .disableAutocorrection(capitalization == .none)
                #endif
                .submitLabel(submitLabel)
                .onSubmit(onReturn)
                .focused($focusedField, equals: field)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier("card-form.\(field)")
                .applyMonospacedDigit(monospaced)
                .applyTextContentType(contentType)
        }
    }

    /// PAN floating-field — wraps `PayabliCardNumberField` (UIKit-backed)
    /// so the PAN row gets native cursor preservation, smart backspace,
    /// and `.creditCardNumber` autofill, while sharing the same visual
    /// chrome as the other fields.
    @ViewBuilder
    private func floatingCardNumberField(
        label: String,
        accessibilityLabel: String,
        error: String?,
        trailing: AnyView? = nil
    ) -> some View {
        let isActive = focusedField == .cardNumber || !viewModel.cardNumber.isEmpty
        // Bidirectional sync between the parent's @FocusState and the
        // representable's `isFocused`. Reads project the focused field; writes
        // claim or release `.cardNumber` on the FocusState.
        let isFocusedBinding = Binding<Bool>(
            get: { focusedField == .cardNumber },
            set: { newValue in
                if newValue {
                    focusedField = .cardNumber
                } else if focusedField == .cardNumber {
                    focusedField = nil
                }
            }
        )

        floatingFieldChrome(
            label: label,
            isActive: isActive,
            isFocused: focusedField == .cardNumber,
            accessibilityLabel: accessibilityLabel,
            error: error,
            trailing: trailing,
            onTap: { focusedField = .cardNumber }
        ) {
            PayabliCardNumberField(
                text: $viewModel.cardNumber,
                isFocused: isFocusedBinding,
                placeholder: "",
                accessibilityLabel: accessibilityLabel,
                accessibilityIdentifier: "card-form.\(CardFormViewModel.Field.cardNumber)",
                onSubmit: { focusedField = .expiration }
            )
        }
    }

    // MARK: - Trailing icons

    /// Card-brand trailing — a multi-brand preview row when empty (filtered
    /// by `allowedBrands`), a single detected brand badge once the user
    /// starts typing.
    @ViewBuilder
    private var cardBrandTrailing: some View {
        if viewModel.cardNumber.isEmpty {
            HStack(spacing: 4) {
                if allowedBrands.contains(.visa)       { CardBrandBadge(brand: .visa) }
                if allowedBrands.contains(.amex)       { CardBrandBadge(brand: .amex) }
                if allowedBrands.contains(.mastercard) { CardBrandBadge(brand: .mastercard) }
                if allowedBrands.contains(.discover)   { CardBrandBadge(brand: .discover) }
            }
        } else {
            CardBrandBadge(brand: viewModel.cardBrand)
        }
    }

    private func hasAnyContent(for field: CardFormViewModel.Field) -> Bool {
        switch field {
        case .holderName: return !viewModel.holderName.isEmpty
        case .cardNumber: return !viewModel.cardNumber.isEmpty
        case .expiration: return !viewModel.expirationText.isEmpty
        case .cvv: return !viewModel.cvv.isEmpty
        case .zip: return !viewModel.zip.isEmpty
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
    /// Presents a card tokenization sheet bound to `isPresented`.
    ///
    /// Swipe-to-dismiss or the "Cancel" button both report
    /// `PayabliGenericError(.userCancelled)`. See PRD FR-6.2, FR-3.2.
    public func payabliCardSheet(
        isPresented: Binding<Bool>,
        customerId: Int,
        theme: PayabliTheme = .default,
        strings: CardFormStrings = .default,
        allowedBrands: PayabliCardBrand = .all,
        onCompletion: @escaping PayabliTokenizationCompletion
    ) -> some View {
        modifier(PayabliCardTokenizeSheetModifier(
            isPresented: isPresented,
            customerId: customerId,
            theme: theme,
            strings: strings,
            allowedBrands: allowedBrands,
            onCompletion: onCompletion
        ))
    }

    /// Presents a card payment sheet bound to `isPresented`.
    ///
    /// See PRD FR-6.7, FR-12A.
    public func payabliCardSheet(
        isPresented: Binding<Bool>,
        paymentRequest: PayabliPaymentRequest,
        customerId: Int,
        theme: PayabliTheme = .default,
        strings: CardFormStrings = .default,
        allowedBrands: PayabliCardBrand = .all,
        onCompletion: @escaping PayabliPaymentCompletion
    ) -> some View {
        modifier(PayabliCardChargeSheetModifier(
            isPresented: isPresented,
            paymentRequest: paymentRequest,
            customerId: customerId,
            theme: theme,
            strings: strings,
            allowedBrands: allowedBrands,
            onCompletion: onCompletion
        ))
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct PayabliCardTokenizeSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let customerId: Int
    let theme: PayabliTheme
    let strings: CardFormStrings
    let allowedBrands: PayabliCardBrand
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
                CardFormView(
                    customerId: customerId,
                    theme: theme,
                    strings: strings,
                    allowedBrands: allowedBrands
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
private struct PayabliCardChargeSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let paymentRequest: PayabliPaymentRequest
    let customerId: Int
    let theme: PayabliTheme
    let strings: CardFormStrings
    let allowedBrands: PayabliCardBrand
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
                CardFormView(
                    paymentRequest: paymentRequest,
                    customerId: customerId,
                    theme: theme,
                    strings: strings,
                    allowedBrands: allowedBrands
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

// MARK: - View modifier helpers

@available(iOS 15.0, macOS 12.0, *)
private extension View {
    /// Applies `.monospacedDigit()` (iOS 15.4+ / macOS 12.3+) only when
    /// `enabled` is true. Falls back to no-op on older OS.
    @ViewBuilder
    func applyMonospacedDigit(_ enabled: Bool) -> some View {
        if enabled {
            if #available(iOS 15.4, macOS 12.3, *) {
                self.monospacedDigit()
            } else {
                self
            }
        } else {
            self
        }
    }

    /// Maps a `CardFormView.TextContentTypeOption` to the underlying iOS
    /// `UITextContentType`. macOS no-ops. The credit-card variants other than
    /// `.creditCardNumber` were added in iOS 17 and are guarded accordingly.
    @ViewBuilder
    func applyTextContentType(_ type: CardFormView.TextContentTypeOption) -> some View {
        #if os(iOS)
        switch type {
        case .none:
            self
        case .creditCardNumber:
            self.textContentType(.creditCardNumber)
        case .creditCardExpiration:
            if #available(iOS 17.0, *) {
                self.textContentType(.creditCardExpiration)
            } else {
                self
            }
        case .creditCardSecurityCode:
            if #available(iOS 17.0, *) {
                self.textContentType(.creditCardSecurityCode)
            } else {
                self
            }
        }
        #else
        self
        #endif
    }
}
