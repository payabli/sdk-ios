import PayabliSDKPayIn
import SwiftUI

/// One screen that captures, authorizes or tokenizes, with the form's customization in reach: pick a preset
/// from the menu, then change any single setting on top of it.
///
/// The two frames mark who draws what: the solid one is this app, the dashed one is the SDK.
struct SimpleCaptureView: View {
    @ObservedObject var captureFlow: PayInFlowHandle
    @ObservedObject var authorizeFlow: PayInFlowHandle
    @ObservedObject var saveFlow: PayInFlowHandle

    @EnvironmentObject private var demoCustomer: DemoCustomerSetting
    @State private var customization = PayInFormCustomization()
    @State private var operation: PayInOperation = .capture
    /// Off by default, and not kept between launches.
    @State private var offersAuthorize = false
    /// The amount each charging flow's attempt was drawn for, so a flow is given a new attempt, and a new key, only
    /// when the amount it would send has changed.
    @State private var attemptAmounts: [PayInOperation: Double] = [:]
    @State private var amountText = AmountEntry.text(for: 10)
    @State private var resultText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OwnerFrame(title: "Your app", dashed: false) {
                        appControls
                    }

                    // A capture or an authorization needs an amount, so without a valid one there is no form to submit.
                    if !charges || enteredAmount != nil {
                        OwnerFrame(title: "Payabli SDK", dashed: true) {
                            PaymentFormHost(
                                flow: flow(for: operation),
                                form: form,
                                // Each form reports for the operation it was built for, which a completion that
                                // lands after the picker has moved still names.
                                onCompleted: { [operation] outcome in handleCompleted(outcome, for: operation) },
                                onFailed: handleFailed
                            )
                            // The form keeps part of its configuration from when it was built, so each
                            // change of setting or of flow builds a new one.
                            .id(FormIdentity(operation: operation, customization: customization))
                        }
                    }

                    if !resultText.isEmpty {
                        Text(resultText)
                            .font(.footnote)
                            .foregroundColor(.payabliOnSurfaceVariant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Simple Capture")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    settingsMenu
                }
            }
        }
        .onAppear {
            applyCustomer(demoCustomer.suppliesPayInCustomer)
            applyAmount()
        }
        .onChange(of: demoCustomer.suppliesPayInCustomer, perform: applyCustomer)
        .onChange(of: amountText) { _ in applyAmount() }
        .onChange(of: operation) { _ in applyAmount() }
    }

    private var appControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Operation", selection: $operation) {
                ForEach(offeredOperations, id: \.self) { operation in
                    Text(Self.name(of: operation)).tag(operation)
                }
            }
            .pickerStyle(.segmented)
            // A submission finishes on the operation it started on, so the screen stays there until it does.
            .disabled(flow(for: operation).isSubmitting)

            if charges {
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .textFieldStyle(.roundedBorder)
                        // The attempt in flight keeps its amount, so the field does too.
                        .disabled(flow(for: operation).isSubmitting)
                        .accessibilityIdentifier("simpleCapture.amount")
                }
                if enteredAmount == nil {
                    Text("A positive amount, up to two decimals.")
                        .font(.footnote)
                        .foregroundColor(.payabliError)
                        .accessibilityIdentifier("simpleCapture.amountError")
                }
            }
        }
    }

    private var enteredAmount: Double? {
        AmountEntry.amount(from: amountText)
    }

    private var charges: Bool {
        operation != .storedMethod
    }

    /// Authorize while the setting is on, and while it is the operation on screen, so turning the setting off never
    /// moves the screen off an authorization. Its flow keeps its attempt and key either way.
    private var offeredOperations: [PayInOperation] {
        let authorize: [PayInOperation] = offersAuthorize || operation == .authorize ? [.authorize] : []
        return [.capture] + authorize + [.storedMethod]
    }

    private static func name(of operation: PayInOperation) -> String {
        switch operation {
        case .capture, .void: "Capture"
        case .authorize: "Authorize"
        case .storedMethod: "Tokenize"
        }
    }

    private func flow(for operation: PayInOperation) -> PayInFlowHandle {
        switch operation {
        case .capture, .void: captureFlow
        case .authorize: authorizeFlow
        case .storedMethod: saveFlow
        }
    }

    private var form: PayInFormSetup {
        PayInFormSetup(
            operation: operation,
            configuration: customization.configuration(for: operation),
            style: customization.style
        )
    }

    // MARK: - The menu

    private var settingsMenu: some View {
        Menu {
            Section("Operations") {
                Toggle("Offer Authorize", isOn: $offersAuthorize)
            }

            Section("Presets") {
                ForEach(PayInFormCustomization.Preset.allCases) { preset in
                    Button {
                        customization = PayInFormCustomization(preset: preset)
                    } label: {
                        if customization.activePreset == preset {
                            Label(preset.rawValue, systemImage: "checkmark")
                        } else {
                            Text(preset.rawValue)
                        }
                    }
                }
            }

            Section("Look") {
                Picker("Look", selection: $customization.look) {
                    ForEach(PayInFormCustomization.Look.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Section("Methods") {
                Picker("Payment methods", selection: $customization.methods) {
                    ForEach(PayInFormCustomization.Methods.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("Start on", selection: $customization.startOn) {
                    Text("Card").tag(PayabliPayInMethodType.card)
                    Text("Bank").tag(PayabliPayInMethodType.bankAccount)
                }
                .pickerStyle(.menu)
                .disabled(customization.methods != .cardAndBank)
            }

            Section("Labels") {
                Toggle("Labels inside the fields", isOn: $customization.labelsInsideFields)
                Toggle("Hide labels", isOn: $customization.hidesLabels)
                Toggle("Custom wording", isOn: $customization.usesCustomWording)
            }

            Section("Hidden values") {
                Toggle("Fixed holder type", isOn: $customization.fixesHolderType)
            }

            Section("Sections") {
                Toggle("Customer section", isOn: $customization.showsCustomerSection)
                Toggle("Customer section first", isOn: $customization.customerSectionFirst)
                    .disabled(!customization.showsCustomerSection)
                Toggle("Require a customer number", isOn: $customization.requiresCustomerNumber)
            }

            Section("Formatting") {
                Toggle("Group the card number", isOn: $customization.groupsCardNumber)
                Toggle("Dash between month and year", isOn: $customization.dashesExpiry)
                Toggle("Mask the account number", isOn: $customization.masksAccountNumber)
            }

            Section("iOS only") {
                Picker("Card brand icon", selection: $customization.cardBrandIconPlacement) {
                    Text("Leading").tag(PayabliPayInCardBrandIconPlacement.leading)
                    Text("Trailing").tag(PayabliPayInCardBrandIconPlacement.trailing)
                    Text("Hidden").tag(PayabliPayInCardBrandIconPlacement.hidden)
                }
                .pickerStyle(.menu)
                Picker("Error message", selection: $customization.errorMessagePlacement) {
                    Text("Top").tag(PayabliPayInErrorMessagePlacement.top)
                    Text("Above button").tag(PayabliPayInErrorMessagePlacement.aboveSubmitButton)
                }
                .pickerStyle(.menu)
                Picker("Input size", selection: $customization.inputSizing) {
                    ForEach(PayInFormCustomization.InputSizing.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("Form settings")
        }
        .accessibilityIdentifier("simpleCapture.menu")
    }

    // MARK: - Actions

    /// Each amount is a new attempt with its own key, on the flow on screen. A flow whose attempt already has this
    /// amount keeps it, and its key, so switching operations never drops a key another attempt may still need.
    /// Not while a submission is in flight, which the handle refuses.
    private func applyAmount() {
        guard charges, let amount = enteredAmount, attemptAmounts[operation] != amount else { return }
        startNewAttempt(amount: amount, for: operation)
    }

    private func startNewAttempt(amount: Double, for operation: PayInOperation) {
        if flow(for: operation).startNewAttempt(
            suppliesCustomer: demoCustomer.suppliesPayInCustomer,
            amount: amount,
            source: PayInFormCustomization.source
        ) {
            attemptAmounts[operation] = amount
        }
    }

    /// The customer choice reaches each charging flow's attempt and leaves its amount and key as they were.
    private func applyCustomer(_ supplies: Bool) {
        captureFlow.applyCustomerChange(suppliesCustomer: supplies)
        authorizeFlow.applyCustomerChange(suppliesCustomer: supplies)
    }

    private func handleCompleted(_ outcome: PayInOutcome, for operation: PayInOperation) {
        if let method = outcome.storedMethod {
            // Never the stored-method id: it charges the card again, and tests keep screenshots of this text.
            resultText = "Saved: \(method.responseText)"
        } else {
            let verb = operation == .authorize ? "Authorized" : "Captured"
            resultText = "\(verb): \(outcome.code), \(outcome.transaction?.paymentTransId ?? "-")"
            // The next submit is a payment of its own.
            if let amount = enteredAmount {
                startNewAttempt(amount: amount, for: operation)
            }
        }
    }

    private func handleFailed(_ failure: PayInFailure) {
        guard !failure.refusedForAnotherSubmission else { return }
        resultText = "Failed: \(failure.message)"
    }
}

private struct FormIdentity: Hashable {
    let operation: PayInOperation
    let customization: PayInFormCustomization
}

/// A labelled border in this app's own colours, whichever style the form is given. The label sits
/// outside the border so it never reads as part of what is inside.
private struct OwnerFrame<Content: View>: View {
    let title: String
    let dashed: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.payabliOnSurfaceVariant)
            content
                .padding(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            Color.payabliOutline,
                            style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [6, 4] : [])
                        )
                )
        }
    }
}

#Preview {
    WithDemoSession { session, _ in
        SimpleCaptureView(
            captureFlow: PayInSessions.preview(session: session, operation: .capture),
            authorizeFlow: PayInSessions.preview(session: session, operation: .authorize),
            saveFlow: PayInSessions.preview(session: session)
        )
        .environmentObject(DemoCustomerSetting())
    }
}
