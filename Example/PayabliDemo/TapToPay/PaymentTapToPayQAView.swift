import PayabliSDKCore
import PayabliSDKTapToPay
import SwiftUI

/// Tap to Pay QA screen.
///
/// Shows every input `PayabliTTP` needs before it can reach `.ready`, flags the
/// ones that are still placeholders, and drives the lifecycle:
///   - **Enable Terminal** — `initialize()`: eligibility → App Attest → `GET /config` →
///     hand credentials to the reader → prepare reader → `.ready`.
///   - **Charge** — `charge(type:paymentDetails:)`, which presents Apple's NFC sheet.
///   - **Activate device** — `activateDevice(activationCode:)` for `.pendingActivation`.
///
/// The values themselves come from `Secrets.swift`; they are read-only here because
/// `PayabliTTP` is constructed once at launch in `PaymentMethodQAApp`.
struct PaymentTapToPayQAView: View {
    @ObservedObject var terminal: PayabliTTP

    @State private var amountText = "1.00"
    @State private var activationCode = ""
    @State private var enableMessage = ""
    @State private var activationMessage = ""
    @State private var chargeMessage = ""
    @State private var tokenCheckText = ""
    @State private var eventLog: [TapToPayQAEventEntry] = []
    @State private var eventToken: PayabliTTPEventToken?
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
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
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
            tokenCheck: TokenCheck.classify(tokenCheckText),
            session: terminal.sessionState,
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
                    .disabled(isWorking)
                    if !tokenCheckText.isEmpty {
                        Text(tokenCheckText)
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

    /// Recovery is not part of the sequence, so it only appears when the session
    /// is in a state it can actually repair.
    @ViewBuilder
    private var recoverySection: some View {
        if steps.nextAction == .reinitialize || steps.nextAction == .reattest {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recovery")
                    .font(.headline)
                Text(steps.nextAction == .reinitialize
                    ? "The session expired. This re-runs config and reader setup without a fresh attestation."
                    : "The session errored. A config 401 clears the attested identity, so this runs the full setup.")
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
    /// form. The self-service route is deliberately a pointer, not a recipe —
    /// the commands live with the server they belong to.
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

    private var sessionBadge: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Text(stateLabel(terminal.sessionState))
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(stateColor(terminal.sessionState).opacity(0.2))
                .foregroundColor(stateColor(terminal.sessionState))
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
        Task {
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
        Task {
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
        Task {
            defer { isWorking = false }
            do {
                let result = try await terminal.charge(
                    type: .sale,
                    paymentDetails: PayabliTTPPaymentDetails(amount: amount),
                    orderDescription: "Tap to Pay sample"
                )
                chargeMessage = "✓ Charged · txn \(result.paymentTransId)"
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
        Task {
            defer { isWorking = false }
            do {
                try await terminal.activateDevice(activationCode: code)
            } catch let error as PayabliTTPError {
                // A revoked attestation resets the session to `.idle`, and the
                // way out is a fresh cold attestation. The reason goes to the
                // step that offers it.
                if case .attestationRevoked = error {
                    activationOutcome = .attestationRevoked
                    enableMessage = "✗ \(error.localizedDescription)"
                    activationMessage = "✗ Attestation revoked — re-enable the terminal, see step 2."
                } else {
                    activationOutcome = .activationFailed
                    activationMessage = "✗ \(error.localizedDescription)"
                }
                return
            } catch {
                activationOutcome = .activationFailed
                activationMessage = "✗ \(error.localizedDescription)"
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
    /// Reports only that a token arrived — never the token itself.
    private func runTokenCheck() {
        isWorking = true
        tokenCheckText = "Checking…"
        Task {
            defer { isWorking = false }
            do {
                _ = try await Secrets.fetchAccessToken()
                tokenCheckText = "✓ Token endpoint returned a token"
            } catch {
                tokenCheckText = "✗ Token endpoint failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Events

    private func subscribeToEvents() {
        guard eventToken == nil else { return }
        // The token owns both the subscription and its tear-down (cancelled in
        // onDisappear). A detached Task over events() would leak across view
        // appearances, since SwiftUI gives no handle to cancel it.
        eventToken = terminal.addEventListener { code, payload in
            let detail = payload.count == 0
                ? ""
                : payload.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", ")
            DispatchQueue.main.async {
                eventLog.insert(
                    TapToPayQAEventEntry(label: name(for: code), detail: detail),
                    at: 0
                )
                if eventLog.count > 100 {
                    eventLog.removeLast(eventLog.count - 100)
                }
            }
        }
    }

    // MARK: - Cosmetics

    /// `PayabliTTPEventCode` is an `@objc Int` enum, so `String(describing:)`
    /// renders `PayabliTTPEventCode(rawValue: 0)` rather than the case name.
    private func name(for code: PayabliTTPEventCode) -> String {
        switch code {
        case .attestationStarted: return "attestationStarted"
        case .attestationCompleted: return "attestationCompleted"
        case .configReceived: return "configReceived"
        case .readerInitializing: return "readerInitializing"
        case .readerReady: return "readerReady"
        case .chargeInitiated: return "chargeInitiated"
        case .nfcStarted: return "nfcStarted"
        case .nfcCompleted: return "nfcCompleted"
        case .nfcFailed: return "nfcFailed"
        case .updateCompleted: return "updateCompleted"
        case .updateFailed: return "updateFailed"
        case .sessionExpired: return "sessionExpired"
        case .reinitializeStarted: return "reinitializeStarted"
        case .reinitializeCompleted: return "reinitializeCompleted"
        case .devicePendingActivation: return "devicePendingActivation"
        case .activationStarted: return "activationStarted"
        case .activationCompleted: return "activationCompleted"
        case .activationFailed: return "activationFailed"
        @unknown default: return "event(\(code.rawValue))"
        }
    }

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
        case .ready: return .payabliSuccess
        case .error, .sessionExpired: return .payabliError
        case .pendingActivation: return .payabliWarning
        default: return .payabliNeutral
        }
    }
}

// MARK: - Models

struct TapToPayQAEventEntry: Identifiable {
    let id = UUID()
    let label: String
    let detail: String
}
