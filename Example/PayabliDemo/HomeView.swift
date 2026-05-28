import PayabliSDKCore
import PayabliSDKTapToPay
import PayabliSDKTokenization
import SwiftUI

/// Demo app landing screen exercising Tap to Pay and tokenization:
///   - `initialize()` — cold/warm attestation + reader prepare.
///   - `charge(type:paymentDetails:)` — full sale pipeline with NFC tap.
///   - `activateDevice(activationCode:)` — pending-device activation.
///   - `events()` — live event log surfaced via `addEventListener`.
///   - `sessionState` — surfaced in the navigation bar as a colored badge.
///   - `PayabliTokenizationView` — configurable card PAN / ACH tokenization.
struct HomeView: View {
    @EnvironmentObject private var ttp: PayabliTTP
    @EnvironmentObject private var tokenization: PayabliTokenization

    @State private var amountText: String = "9.99"
    @State private var activationCode: String = ""
    @State private var lastResult: String = ""
    @State private var tokenizationResult: String = ""
    @State private var eventLog: [EventLogEntry] = []
    @State private var eventToken: PayabliTTPEventToken?
    @State private var presentingActivation = false
    @State private var isWorking = false

    var body: some View {
        TabView {
            tapToPayTab
                .tabItem {
                    Label("Tap to Pay", systemImage: "wave.3.right")
                }

            tokenizationTab
                .tabItem {
                    Label("Tokenize", systemImage: "creditcard")
                }
        }
    }

    private var tapToPayTab: some View {
        NavigationView {
            List {
                stateSection
                saleSection
                resultSection
                eventLogSection
            }
            .navigationTitle("Tap to Pay Demo")
            .toolbar { sessionBadge }
            .sheet(isPresented: $presentingActivation) { activationSheet }
            .onAppear(perform: subscribeToEvents)
            .onDisappear { eventToken?.cancel() }
        }
    }

    private var tokenizationTab: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PayabliTokenizationView(
                        component: tokenization,
                        configuration: tokenizationConfiguration,
                        onTokenized: { method in
                            tokenizationResult = [
                                "Stored method: \(method.storedMethodId ?? "—")",
                                "Response: \(method.responseText)",
                                "Result: \(method.resultText ?? "—")"
                            ].joined(separator: "\n")
                        },
                        onError: { error in
                            tokenizationResult = "Tokenization failed: \(error.localizedDescription)"
                        }
                    )
                    .payabliTokenizationStyle(tokenizationStyle)

                    Text(tokenizationResult.isEmpty ? "No tokenization result yet" : tokenizationResult)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(16)
            }
            .navigationTitle("Tokenization")
        }
    }

    // MARK: - Sections

    private var stateSection: some View {
        Section("Lifecycle") {
            Button("Initialize") { runInitialize() }
                .disabled(isWorking || ttp.isReady)
            Button("Re-initialize if needed") { runReinitialize() }
                .disabled(isWorking)
            Button("Activate device…") { presentingActivation = true }
                .disabled(isWorking)
        }
    }

    private var saleSection: some View {
        Section("Sale") {
            HStack {
                Text("$")
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
            }
            Button("Charge") { runCharge() }
                .disabled(isWorking || !ttp.isReady)
        }
    }

    private var tokenizationConfiguration: PayabliTokenizationFormConfiguration {
        PayabliTokenizationFormConfiguration(
            allowedMethods: [.card, .ach],
            defaultMethod: .card,
            cardFieldOrder: [
                .cardholderName,
                .cardNumber,
                .cardExpiration,
                .cardCvv,
                .cardZip
            ],
            achFieldOrder: [
                .achHolder,
                .achRouting,
                .achAccount,
                .achAccountType
            ],
            hiddenValues: PayabliTokenizationHiddenValues(
                achHolderType: .personal,
                achSecCode: .web,
                methodDescription: "Demo stored method"
            ),
            options: PayabliTokenizationOptions(
                achValidation: true,
                createAnonymous: false,
                forceCustomerCreation: true,
                temporary: false,
                source: "ios-demo"
            ),
            labels: PayabliTokenizationLabels(
                title: "Save Payment Method",
                subtitle: "Create a card or ACH token from sandbox data."
            ),
            labelLayout: .external,
            formatting: PayabliTokenizationFormatting(
                insertsCardNumberSpaces: true,
                masksACHAccountEntry: true
            ),
            inputSizing: PayabliTokenizationInputSizing(
                defaultSize: PayabliTokenizationInputSize(height: 52),
                fieldSizes: [
                    .cardExpiration: PayabliTokenizationInputSize(height: 48),
                    .cardCvv: PayabliTokenizationInputSize(height: 48)
                ]
            ),
            cardBrandIconPlacement: .trailing
        )
    }

    private var tokenizationStyle: PayabliTokenizationStyle {
        PayabliTokenizationStyle(
            accentColor: .green,
            input: PayabliTokenizationInputStyle(
                backgroundColor: Color(.systemBackground),
                borderColor: Color(.separator).opacity(0.6),
                cornerRadius: 8
            ),
            submitButton: PayabliTokenizationSubmitButtonStyle(cornerRadius: 8),
            layout: PayabliTokenizationLayoutStyle(contentSpacing: 18, fieldGroupSpacing: 12)
        )
    }

    private var resultSection: some View {
        Section("Last result") {
            Text(lastResult.isEmpty ? "—" : lastResult)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var eventLogSection: some View {
        Section("Event log") {
            if eventLog.isEmpty {
                Text("No events yet")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(eventLog) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.label).font(.footnote.bold())
                        if !entry.detail.isEmpty {
                            Text(entry.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            Button("Clear log", role: .destructive) { eventLog.removeAll() }
                .disabled(eventLog.isEmpty)
        }
    }

    private var sessionBadge: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Text(stateLabel(ttp.sessionState))
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(stateColor(ttp.sessionState).opacity(0.2))
                .foregroundColor(stateColor(ttp.sessionState))
                .clipShape(Capsule())
        }
    }

    private var activationSheet: some View {
        NavigationView {
            Form {
                Section("Activation code") {
                    TextField("Code from Payabli ops", text: $activationCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Button("Activate") {
                    presentingActivation = false
                    runActivate()
                }
                .disabled(activationCode.isEmpty)
            }
            .navigationTitle("Activate device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentingActivation = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func runInitialize() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await ttp.initialize()
                lastResult = "✓ Initialized"
            } catch {
                lastResult = "✗ Initialize failed: \(error.localizedDescription)"
            }
        }
    }

    private func runReinitialize() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await ttp.reinitializeIfNeeded()
                lastResult = "✓ Re-initialized (or already ready)"
            } catch {
                lastResult = "✗ Re-initialize failed: \(error.localizedDescription)"
            }
        }
    }

    private func runCharge() {
        guard let amount = Decimal(string: amountText) else {
            lastResult = "✗ Invalid amount"
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let result = try await ttp.charge(
                    type: .sale,
                    paymentDetails: PayabliTTPPaymentDetails(amount: amount)
                )
                lastResult = "✓ Charged · txn \(result.paymentTransId)"
            } catch {
                lastResult = "✗ Charge failed: \(error.localizedDescription)"
            }
        }
    }

    private func runActivate() {
        let code = activationCode
        activationCode = ""
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await ttp.activateDevice(activationCode: code)
                lastResult = "✓ Device activated"
            } catch {
                lastResult = "✗ Activation failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Event subscription

    private func subscribeToEvents() {
        guard eventToken == nil else { return }
        // Single source of truth: the addEventListener token owns both the
        // subscription *and* its tear-down (cancelled in onDisappear). Using
        // events() with a separate detached Task here would leak that Task
        // across view appearances since SwiftUI gives us no handle to cancel
        // it from onDisappear.
        eventToken = ttp.addEventListener { code, payload in
            let detail: String = if payload.count == 0 {
                ""
            } else {
                payload
                    .map { "\($0.key): \($0.value)" }
                    .sorted()
                    .joined(separator: ", ")
            }
            DispatchQueue.main.async {
                eventLog.insert(
                    EventLogEntry(label: String(describing: code), detail: detail),
                    at: 0
                )
                if eventLog.count > 100 {
                    eventLog.removeLast(eventLog.count - 100)
                }
            }
        }
    }

    // MARK: - Cosmetics

    private func stateLabel(_ state: PayabliTTPSessionState) -> String {
        switch state {
        case .idle: return "idle"
        case .attestingDevice: return "attesting"
        case .fetchingConfig: return "config"
        case .initializingReader: return "reader"
        case .ready: return "ready"
        case .sessionExpired: return "expired"
        case .reinitializing: return "reinit"
        case .pendingActivation: return "pending"
        case .error: return "error"
        @unknown default: return "?"
        }
    }

    private func stateColor(_ state: PayabliTTPSessionState) -> Color {
        switch state {
        case .ready: return .green
        case .error, .sessionExpired: return .red
        case .pendingActivation: return .orange
        default: return .gray
        }
    }
}

// MARK: - Models

private struct EventLogEntry: Identifiable {
    let id = UUID()
    let label: String
    let detail: String
}
