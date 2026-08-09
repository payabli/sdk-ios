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
    @State private var resultText = ""
    @State private var tokenCheckText = ""
    @State private var eventLog: [TapToPayQAEventEntry] = []
    @State private var eventToken: PayabliTTPEventToken?
    @State private var isActivationPresented = false
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    configurationSection
                    TerminalReadinessView(configuredAppId: Secrets.appId)
                    enableTerminalButton
                    saleSection
                    activationSection
                    resultSection
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

    // MARK: - Configuration

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terminal configuration")
                .font(.headline)

            Text("What the SDK needs before it can initialize. Edit these in `Secrets.swift`.")
                .font(.caption)
                .foregroundColor(.payabliOnSurfaceVariant)

            QADetailRow(
                label: "Entry point",
                value: Secrets.entryPoint,
                problem: Secrets.entryPoint.isEmpty ? "Empty — /config is keyed by entry point." : nil
            )
            QADetailRow(
                label: "App ID",
                value: Secrets.appId,
                problem: nil
            )
            QADetailRow(
                label: "Environment",
                value: "\(environmentName) · "
                    + (DemoConfiguration.environment.baseURL.host ?? "—"),
                problem: nil
            )
            QADetailRow(
                label: "Token endpoint",
                value: Secrets.partnerTokenEndpoint.absoluteString
                    + "\n(\(DemoConfiguration.TokenServer.explanation))",
                problem: nil
            )

            Button {
                runTokenCheck()
            } label: {
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

    /// `PayabliEnvironment` is an `@objc Int` enum, so string interpolation prints
    /// `PayabliEnvironment(rawValue: 1)` rather than the case name.
    private var environmentName: String {
        switch DemoConfiguration.environment {
        case .qa: return "qa"
        case .sandbox: return "sandbox"
        case .production: return "production"
        default: return "other"
        }
    }


    // MARK: - Readiness

    // MARK: - Lifecycle

    private var enableTerminalButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                runEnableTerminal()
            } label: {
                Label(
                    terminal.isReady ? "Terminal enabled" : "Enable Terminal",
                    systemImage: terminal.isReady ? "checkmark.seal.fill" : "wave.3.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || terminal.isReady)

            Button {
                runReinitialize()
            } label: {
                Label("Re-initialize if needed", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
        }
    }

    private var saleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sale")
                .font(.headline)

            HStack {
                Text("$")
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                runCharge()
            } label: {
                Label("Charge (tap card)", systemImage: "creditcard.and.123")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || !terminal.isReady)

            if !terminal.isReady {
                Text("Enable the terminal first — charging needs a prepared reader.")
                    .font(.caption)
                    .foregroundColor(.payabliOnSurfaceVariant)
            }
        }
    }

    private var activationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activation")
                .font(.headline)

            Button {
                isActivationPresented = true
            } label: {
                Label("Activate device…", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)

            Text("Needed when the session reports `pendingActivation`. The code comes from Payabli ops.")
                .font(.caption)
                .foregroundColor(.payabliOnSurfaceVariant)
        }
    }

    private var activationSheet: some View {
        NavigationStack {
            Form {
                Section("Activation code") {
                    TextField("Code from Payabli ops", text: $activationCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Button("Activate") {
                    isActivationPresented = false
                    runActivate()
                }
                .disabled(activationCode.isEmpty)
            }
            .navigationTitle("Activate device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isActivationPresented = false }
                }
            }
        }
    }

    // MARK: - Output

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last result")
                .font(.headline)

            Text(resultText.isEmpty ? "No Tap to Pay result yet" : resultText)
                .font(.footnote)
                .foregroundColor(.payabliOnSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.payabliSurfaceContainer)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

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
                resultText = "✓ Terminal enabled — reader ready"
            } catch {
                resultText = "✗ Enable Terminal failed: \(error.localizedDescription)"
            }
        }
    }

    private func runReinitialize() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await terminal.reinitializeIfNeeded()
                resultText = "✓ Re-initialized (or already ready)"
            } catch {
                resultText = "✗ Re-initialize failed: \(error.localizedDescription)"
            }
        }
    }

    private func runCharge() {
        guard let amount = Decimal(string: amountText), amount > 0 else {
            resultText = "✗ Enter an amount greater than zero"
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
                resultText = "✓ Charged · txn \(result.paymentTransId)"
            } catch {
                resultText = "✗ Charge failed: \(error.localizedDescription)"
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
                resultText = "✓ Device activated"
            } catch {
                resultText = "✗ Activation failed: \(error.localizedDescription)"
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
