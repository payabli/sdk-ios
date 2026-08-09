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
    @State private var isWorking = false

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
            .navigationTitle("Tap to Pay QA")
            .toolbar { sessionBadge }
            .sheet(isPresented: $isActivationPresented) { activationSheet }
            .onAppear(perform: subscribeToEvents)
            .onDisappear {
                eventToken?.cancel()
                eventToken = nil
            }
        }
    }

    // MARK: - The sequence

    /// The order the SDK enforces, made visible. Every status is derived from
    /// `sessionState` rather than tracked separately, so the screen cannot
    /// disagree with the session it is describing.
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steps")
                .font(.headline)

            QAStepRow(
                index: 1,
                title: "Reach the token backend",
                detail: "The SDK calls your backend for a fresh access token whenever it needs one.",
                status: tokenStepStatus
            ) {
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

            QAStepRow(
                index: 2,
                title: "Enable the terminal",
                detail: "Attests the device, fetches the merchant config, and prepares the reader.",
                status: enableStepStatus
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Button { runEnableTerminal() } label: {
                        Label("Enable Terminal", systemImage: "wave.3.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                    stepOutcome(enableMessage)
                }
            }

            QAStepRow(
                index: 3,
                title: "Activate the device",
                detail: activationDetail,
                status: activationStepStatus
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Button { isActivationPresented = true } label: {
                        Label("Enter activation code", systemImage: "checkmark.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                    stepOutcome(activationMessage)
                }
            }

            QAStepRow(
                index: 4,
                title: "Charge a card",
                detail: "Presents Apple's Tap to Pay sheet. Hold a card to the top of the phone.",
                status: chargeStepStatus
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("$")
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button { runCharge() } label: {
                        Label("Charge (tap card)", systemImage: "creditcard.and.123")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                    stepOutcome(chargeMessage)
                }
            }
        }
    }

    /// Recovery is not part of the sequence, so it only appears when the session
    /// is in a state it can actually repair.
    @ViewBuilder
    private var recoverySection: some View {
        if isRecoverable {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recovery")
                    .font(.headline)
                Text("The session expired or errored. This re-runs config and reader setup without a fresh attestation.")
                    .font(.caption)
                    .foregroundColor(.payabliOnSurfaceVariant)
                Button { runReinitialize() } label: {
                    Label("Re-initialize", systemImage: "arrow.clockwise")
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

    // MARK: - Step status, derived from the session

    /// True once the backend is known reachable — either because the check was
    /// run here, or because the SDK already fetched a token to get past `idle`.
    private var backendProven: Bool {
        if tokenCheckText.hasPrefix("✓") { return true }
        return terminal.sessionState != .idle
    }

    private var tokenStepStatus: QAStepStatus {
        if tokenCheckText.hasPrefix("✗") { return .failed }
        return backendProven ? .done : .current
    }

    private var enableStepStatus: QAStepStatus {
        // Exactly one step is ever `.current`, so this stays blocked until the
        // backend is proven rather than competing with step 1 for attention.
        guard backendProven else { return .blocked }
        switch terminal.sessionState {
        case .ready: return .done
        case .attestingDevice, .fetchingConfig, .initializingReader, .reinitializing: return .inProgress
        case .pendingActivation: return .done
        case .error, .sessionExpired: return .failed
        case .idle: return .current
        @unknown default: return .current
        }
    }

    private var activationStepStatus: QAStepStatus {
        switch terminal.sessionState {
        case .pendingActivation: return .current
        case .ready: return .notNeeded
        default: return .blocked
        }
    }

    private var activationDetail: String {
        return terminal.sessionState == .pendingActivation
            ? "Activate the device with the code provided by the Paypoint Device Management dashboard."
            : "Only when the backend registers the device as pending."
    }

    private var chargeStepStatus: QAStepStatus {
        terminal.isReady ? .current : .blocked
    }

    private var isRecoverable: Bool {
        switch terminal.sessionState {
        case .sessionExpired, .error: return true
        default: return false
        }
    }

    private var activationSheet: some View {
        NavigationStack {
            Form {
                Section("Activation code") {
                    TextField("6 digits", text: $activationCode)
                        .keyboardType(.numberPad)
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

    /// A step's own result, in the step. Previously every outcome went to one
    /// shared box at the bottom, so a failure said "failed" here and explained
    /// itself somewhere else.
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
                        "Self-service, for local QA",
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

    private func runEnableTerminal() {
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
                    orderDescription: "Tap to Pay QA"
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
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await terminal.activateDevice(activationCode: code)
                // Activation leaves the session `.idle`, not `.ready` — the
                // device is approved but nothing has been set up yet. Re-running
                // initialize here is what the SDK expects, and it keeps the
                // sequence moving forward instead of dropping back a step.
                activationMessage = "✓ Activated — enabling the terminal"
                try await terminal.initialize()
                activationMessage = "✓ Activated and terminal enabled"
            } catch {
                activationMessage = "✗ \(error.localizedDescription)"
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
    /// Measured on a real `initialize()` run before this existed.
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
