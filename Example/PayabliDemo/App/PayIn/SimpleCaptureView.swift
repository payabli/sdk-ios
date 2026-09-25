import PayabliSDKPayInPaymentFlow
import SwiftUI

/// One screen that captures or tokenizes, with the form's customization in reach: pick a preset
/// from the menu, then change any single setting on top of it.
///
/// The two frames mark who draws what: the solid one is this app, the dashed one is the SDK.
struct SimpleCaptureView: View {
    @ObservedObject var captureFlow: PayInFlowHandle
    @ObservedObject var saveFlow: PayInFlowHandle

    @EnvironmentObject private var demoCustomer: DemoCustomerSetting
    @State private var customization = PayInFormCustomization()
    @State private var capturing = true
    @State private var amountText = AmountEntry.text(for: 10)
    @State private var resultText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OwnerFrame(title: "Your app", dashed: false) {
                        appControls
                    }

                    // A capture needs an amount, so without a valid one there is no form to submit.
                    if !capturing || enteredAmount != nil {
                        OwnerFrame(title: "Payabli SDK", dashed: true) {
                            PaymentFormHost(
                                flow: capturing ? captureFlow : saveFlow,
                                form: form,
                                onCompleted: handleCompleted,
                                onFailed: handleFailed
                            )
                            // The form keeps part of its configuration from when it was built, so each
                            // change of setting or of flow builds a new one.
                            .id(FormIdentity(capturing: capturing, customization: customization))
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
        .onAppear(perform: applyAmount)
        .onChange(of: amountText) { _ in applyAmount() }
    }

    private var appControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Operation", selection: $capturing) {
                Text("Capture").tag(true)
                Text("Tokenize").tag(false)
            }
            .pickerStyle(.segmented)

            if capturing {
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .textFieldStyle(.roundedBorder)
                        // The attempt in flight keeps its amount, so the field does too.
                        .disabled(captureFlow.isSubmitting)
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

    private var form: PayInFormSetup {
        PayInFormSetup(
            operation: capturing ? .capture : .storedMethod,
            configuration: customization.configuration(capturing: capturing),
            style: customization.style
        )
    }

    // MARK: - The menu

    private var settingsMenu: some View {
        Menu {
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
                    Text("Card").tag(PayabliPayInPaymentFlowMethodType.card)
                    Text("Bank").tag(PayabliPayInPaymentFlowMethodType.bankAccount)
                }
                .pickerStyle(.menu)
                .disabled(customization.methods != .cardAndBank)
            }

            Section("Labels") {
                Toggle("Labels inside the fields", isOn: $customization.labelsInsideFields)
                Toggle("Hide labels", isOn: $customization.hidesLabels)
                Toggle("Custom wording", isOn: $customization.usesCustomWording)
            }

            Section("Sections") {
                Toggle("Customer section", isOn: $customization.showsCustomerSection)
                Toggle("Customer section first", isOn: $customization.customerSectionFirst)
                    .disabled(!customization.showsCustomerSection)
                Toggle("Require a customer number", isOn: $customization.requiresCustomerNumber)
                Toggle("Summary heading", isOn: $customization.titlesAmountSummary)
            }

            Section("Formatting") {
                Toggle("Group the card number", isOn: $customization.groupsCardNumber)
                Toggle("Dash between month and year", isOn: $customization.dashesExpiry)
                Toggle("Mask the account number", isOn: $customization.masksAccountNumber)
            }

            Section("iOS only") {
                Picker("Card brand icon", selection: $customization.cardBrandIconPlacement) {
                    Text("Leading").tag(PayabliPayInPaymentFlowCardBrandIconPlacement.leading)
                    Text("Trailing").tag(PayabliPayInPaymentFlowCardBrandIconPlacement.trailing)
                    Text("Hidden").tag(PayabliPayInPaymentFlowCardBrandIconPlacement.hidden)
                }
                .pickerStyle(.menu)
                Picker("Error message", selection: $customization.errorMessagePlacement) {
                    Text("Top").tag(PayabliPayInPaymentFlowErrorMessagePlacement.top)
                    Text("Above button").tag(PayabliPayInPaymentFlowErrorMessagePlacement.aboveSubmitButton)
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

    /// Each amount is a new attempt with its own key. Not while a submission is in flight, which the
    /// handle refuses.
    private func applyAmount() {
        guard let amount = enteredAmount else { return }
        _ = captureFlow.startNewAttempt(
            suppliesCustomer: demoCustomer.suppliesPayInCustomer,
            amount: amount,
            source: PayInFormCustomization.source
        )
    }

    private func handleCompleted(_ outcome: PayInOutcome) {
        if let method = outcome.storedMethod {
            resultText = "Saved: \(method.storedMethodId ?? "-")\n\(method.responseText)"
        } else {
            resultText = "Captured: \(outcome.code), \(outcome.transaction?.paymentTransId ?? "-")"
            // The next submit is a payment of its own.
            applyAmount()
        }
    }

    private func handleFailed(_ failure: PayInFailure) {
        guard !failure.refusedForAnotherSubmission else { return }
        resultText = "Failed: \(failure.message)"
    }
}

private struct FormIdentity: Hashable {
    let capturing: Bool
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
    SimpleCaptureView(
        captureFlow: PayInSessions.preview(capturing: true),
        saveFlow: PayInSessions.preview()
    )
    .environmentObject(DemoCustomerSetting())
}
