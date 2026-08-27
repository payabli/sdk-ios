import SwiftUI

/// Tap to Pay QA screen.
///
/// Shows every input the reader needs before it can become ready, flags the
/// ones that are still placeholders, and drives the lifecycle:
///   - **Enable Terminal** — `initialize()`: eligibility → App Attest → `GET /config` →
///     hand credentials to the reader → prepare reader → `.ready`.
///   - **Charge** — `charge(type:paymentDetails:)`, which presents Apple's NFC sheet.
///   - **Activate device** — `activateDevice(activationCode:)` for `.pendingActivation`.
///
/// The values themselves come from `Secrets.swift`; they are read-only here because
/// the terminal is constructed once at launch, in the app's entry point.
struct PaymentTapToPayQAView: View {
    @ObservedObject var terminal: TapToPayTerminal

    @EnvironmentObject private var tokenProbes: TokenProbeResults
    @EnvironmentObject private var demoCustomer: DemoCustomerSetting
    @State private var amountText = "1.00"
    @State private var activationCode = ""
    @State private var enableMessage = ""
    @State private var activationMessage = ""
    @State private var chargeMessage = ""
    @State private var eventLog: [TapToPayQAEventEntry] = []
    @State private var eventToken: TapToPayEventSubscription?
    @State private var isActivationPresented = false
    @State private var isActivationHelpPresented = false
    @State private var activationOutcome = TapToPayActivationOutcome.none
    @State private var isWorking = false
    @FocusState private var focusedField: Field?

    /// The two numeric-keypad fields. A decimal or number pad has no return key,
    /// so the screen has to offer the dismissal itself; without one the keyboard
    /// covers the tab bar and the event log, and nothing on screen gets it back.
    private enum Field: Hashable {
        case amount
        case activationCode
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    QAContextLine()
                    TerminalReadinessView(configuredAppId: Secrets.appId)
                    stepsSection
                    recoverySection
                    eventLogSection
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Tap to Pay")
            .toolbar { sessionBadge }
            // Not `ToolbarItemGroup(placement: .keyboard)`, which was declared
            // here and never appeared, leaving the number pad with no way out.
            .safeAreaInset(edge: .bottom) { keyboardDismissBar }
            .sheet(isPresented: $isActivationPresented) { activationSheet }
            .onAppear(perform: subscribeToEvents)
            .onDisappear {
                eventToken?.cancel()
                eventToken = nil
            }
        }
    }

    // MARK: - The sequence

    /// The order the SDK enforces, made visible. Derived in one place, so no two
    /// steps can disagree about which is next.
    private var steps: TapToPayFlowSteps {
        TapToPaySteps.forCharging(
            tokenCheck: tokenProbes.check(.cardPresent),
            session: terminal.status,
            activation: activationOutcome
        )
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steps")
                .font(.headline)

            StepRow(index: 1, step: steps.token) {
                VStack(alignment: .leading, spacing: 6) {
                    Button { runTokenCheck() } label: {
                        Label("Check token endpoint", systemImage: "key.horizontal")
                    }
                    .buttonStyle(.bordered)
                    // `isWorking` covers this screen's own operations. The probe
                    // is shared, so a run started on another tab is this step's
                    // `.inProgress` and only the derived step knows it.
                    .disabled(isWorking || tokenProbes.isRunning(.cardPresent))
                    if !tokenProbes.display(for: .cardPresent).isEmpty {
                        Text(tokenProbes.display(for: .cardPresent))
                            .font(.caption)
                            .foregroundColor(.payabliOnSurfaceVariant)
                    }
                }
            }

            StepRow(index: 2, step: steps.enable) {
                VStack(alignment: .leading, spacing: 6) {
                    if steps.nextAction == .enableTerminal {
                        Button { runEnableTerminal() } label: {
                            Label("Enable Terminal", systemImage: "wave.3.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking)
                    }
                    stepOutcome(enableMessage)
                }
            }

            StepRow(index: 3, step: steps.activation) {
                VStack(alignment: .leading, spacing: 6) {
                    if steps.nextAction == .enterActivationCode {
                        Button { isActivationPresented = true } label: {
                            Label("Enter activation code", systemImage: "checkmark.shield")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking)
                    }
                    stepOutcome(activationMessage)
                }
            }

            StepRow(index: 4, step: steps.charge) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("$")
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .amount)
                            .textFieldStyle(.roundedBorder)
                    }
                    if steps.nextAction == .charge {
                        Button { runCharge() } label: {
                            Label("Charge (tap card)", systemImage: "creditcard.and.123")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking)
                    }
                    stepOutcome(chargeMessage)
                }
            }
        }
    }

    private func recoveryDetail(_ recovery: TapToPayRecovery) -> String {
        switch recovery {
        case .sessionExpired:
            "The session expired. This re-runs config and reader setup without a fresh attestation."
        case .sessionErrored:
            "The session errored. This runs the full setup, re-using the attested identity when it is still held and attesting again when it is not."
        }
    }

    /// Recovery is not part of the sequence, so it only appears when the session
    /// is in a state it can actually repair.
    @ViewBuilder
    private var recoverySection: some View {
        if let recovery = steps.recovery {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recovery")
                    .font(.headline)
                Text(recoveryDetail(recovery))
                    .font(.caption)
                    .foregroundColor(.payabliOnSurfaceVariant)
                Button {
                    steps.nextAction == .reinitialize ? runReinitialize() : runEnableTerminal()
                } label: {
                    Label(
                        steps.nextAction == .reinitialize ? "Re-initialize" : "Run full setup",
                        systemImage: "arrow.clockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }
            .padding(12)
            .background(Color.payabliSurfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var activationSheet: some View {
        NavigationStack {
            Form {
                Section("Activation code") {
                    TextField("6 digits", text: $activationCode)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .activationCode)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("Provided by the Paypoint Device Management dashboard.")
                        .font(.caption)
                        .foregroundColor(.payabliOnSurfaceVariant)
                    Button("Where do I get a code?") { isActivationHelpPresented = true }
                        .font(.caption)
                }
                Button("Activate") {
                    isActivationPresented = false
                    runActivate()
                }
                .disabled(activationCode.isEmpty)
            }
            .navigationTitle("Activate device")
            .sheet(isPresented: $isActivationHelpPresented) { activationHelpSheet }
            // A sheet is its own hierarchy, so the bar on the screen behind it does
            // not reach the number pad this field raises.
            .safeAreaInset(edge: .bottom) { keyboardDismissBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isActivationPresented = false }
                }
            }
        }
    }

    /// A step's own result, rendered in the step, so a failure states its reason
    /// where it happened rather than in a shared box elsewhere.
    @ViewBuilder
    private func stepOutcome(_ message: String) -> some View {
        if !message.isEmpty {
            Text(message)
                .font(.caption)
                .foregroundColor(message.hasPrefix("✗") ? .payabliError : .payabliOnSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    /// Longer than a caption, so it gets its own sheet rather than crowding the
    /// form. The self-service route is a pointer rather than a recipe: the
    /// commands live with the server they belong to.
    ///
    /// Each paragraph is a single-line literal. A multi-line literal with `\`
    /// continuations keeps the indentation of every continued line as real
    /// spaces, which renders as gaps in the middle of sentences.
    private var activationHelpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpSection(
                        "From the dashboard",
                        [
                            "Payabli paypoint portal → **Device Management** → find this device → options → **Activate device**.",
                            "The code is issued server-side against this device id, and is never generated on the phone."
                        ]
                    )

                    Divider()

                    helpSection(
                        "Self-service, for local testing",
                        [
                            "The bundled token server can list devices and request a code for one.",
                            "See `LocalTokenServer/README.md`, section “Tap to Pay Device Activation”, for the endpoints and what they return."
                        ]
                    )

                    Divider()

                    helpSection(
                        "Additional constraints",
                        [
                            "Six digits, zero-padded. A leading zero matters, so keep it as text.",
                            "Valid for 30 minutes. Five wrong attempts discard it and a new one must be issued.",
                            "Requesting again inside the window returns the same code rather than a new one."
                        ]
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Getting a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isActivationHelpPresented = false }
                }
            }
        }
    }

    private func helpSection(_ title: String, _ paragraphs: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.callout)
                    .foregroundColor(.payabliOnSurface)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Output

    private var eventLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Event log")
                    .font(.headline)
                Spacer()
                Button("Clear", role: .destructive) { eventLog.removeAll() }
                    .font(.footnote)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(eventLog.isEmpty)
            }

            if eventLog.isEmpty {
                Text("No events yet")
                    .font(.footnote)
                    .foregroundColor(.payabliOnSurfaceVariant)
            } else {
                ForEach(eventLog) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.label)
                            .font(.caption.monospaced().bold())
                        if !entry.detail.isEmpty {
                            Text(entry.detail)
                                .font(.caption.monospaced())
                                .foregroundColor(.payabliOnSurfaceVariant)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.payabliSurfaceContainerHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    /// Shown only while a field is being edited, so it takes no height from the
    /// form the rest of the time.
    @ViewBuilder
    private var keyboardDismissBar: some View {
        if focusedField != nil {
            HStack {
                Spacer()
                // A checkmark, matching the accessory the SDK's own fields carry,
                // and it needs no translation. The frame is on the button rather
                // than the row: padding around it leaves its own target smaller
                // than the 44 points a finger is measured against.
                Button {
                    focusedField = nil
                } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Done")
                .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 16)
            .background(.bar)
        }
    }

    private var sessionBadge: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Text(terminal.status.label)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color(for: terminal.status.severity).opacity(0.2))
                .foregroundColor(color(for: terminal.status.severity))
                .clipShape(Capsule())
        }
    }

    // MARK: - Actions

    /// Clears what the previous session said about itself. Each message
    /// describes one attempt, so a failure that has since been repaired must not
    /// sit under a step that is ready to run again.
    private func clearOutcomesForNewSession() {
        enableMessage = ""
        chargeMessage = ""
        activationMessage = ""
        activationOutcome = .none
    }

    private func runEnableTerminal() {
        clearOutcomesForNewSession()
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await terminal.initialize()
                enableMessage = "✓ Reader ready"
            } catch {
                enableMessage = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func runReinitialize() {
        clearOutcomesForNewSession()
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await terminal.reinitializeIfNeeded()
                enableMessage = "✓ Re-initialized"
            } catch {
                enableMessage = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func runCharge() {
        chargeMessage = ""
        guard let amount = Decimal(string: amountText), amount > 0 else {
            chargeMessage = "✗ Enter an amount greater than zero"
            return
        }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let paymentTransId = try await terminal.charge(
                    amount: amount,
                    suppliesCustomer: demoCustomer.suppliesDemoCustomer
                )
                chargeMessage = "✓ Charged · txn \(paymentTransId)"
            } catch {
                chargeMessage = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func runActivate() {
        let code = activationCode
        activationCode = ""
        activationOutcome = .none
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await terminal.activate(code: code)
            } catch let failure as TapToPayFailure {
                // A revoked attestation resets the session to idle, and the way
                // out is a fresh cold attestation. The reason goes to the step
                // that offers it.
                if failure.isAttestationRevoked {
                    activationOutcome = .attestationRevoked
                    enableMessage = "✗ \(failure.message)"
                    activationMessage = "✗ Attestation revoked — re-enable the terminal, see step 2."
                } else {
                    activationOutcome = .activationFailed
                    activationMessage = "✗ \(failure.message)"
                }
                return
            }

            // Activation leaves the session `.idle`, not `.ready` — the device is
            // approved but nothing has been set up yet. Re-running initialize here
            // is what the SDK expects, and it keeps the sequence moving forward
            // instead of dropping back a step. A failure from here belongs to the
            // enable step, which reports it, not to activation, which succeeded.
            activationMessage = "✓ Activated — enabling the terminal"
            do {
                try await terminal.initialize()
                activationOutcome = .succeeded
                activationMessage = "✓ Activated and terminal enabled"
            } catch {
                // The reason belongs to the step that renders it. Step 2 shows
                // `enableMessage`, and the activation row is not `.failed` here,
                // so writing only to `activationMessage` would discard the error.
                activationOutcome = .enableFailed
                enableMessage = "✗ \(error.localizedDescription)"
                activationMessage = "✓ Activated. Enabling the terminal failed — see step 2."
            }
        }
    }

    /// Confirms the partner backend answers before `initialize()` depends on it.
    private func runTokenCheck() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            await tokenProbes.probeCardPresent()
        }
    }

    // MARK: - Events

    private func subscribeToEvents() {
        guard eventToken == nil else { return }
        // The token owns both the subscription and its tear-down (cancelled in
        // onDisappear). A detached Task over events() would leak across view
        // appearances, since SwiftUI gives no handle to cancel it.
        eventToken = terminal.addEventListener { event in
            DispatchQueue.main.async {
                eventLog.insert(
                    TapToPayQAEventEntry(label: event.label, detail: event.detail),
                    at: 0
                )
                if eventLog.count > 100 {
                    eventLog.removeLast(eventLog.count - 100)
                }
            }
        }
    }

    // MARK: - Cosmetics

    private func color(for severity: TapToPayStatusSeverity) -> Color {
        switch severity {
        case .ready: return .payabliSuccess
        case .failed: return .payabliError
        case .waiting: return .payabliWarning
        case .working: return .payabliNeutral
        }
    }
}

// MARK: - Models

struct TapToPayQAEventEntry: Identifiable {
    let id = UUID()
    let label: String
    let detail: String
}
