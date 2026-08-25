import PayabliSDKCore
import PayabliSDKPayInPaymentFlow
import SwiftUI

/// Every knob the demo runs on, in one place.
///
/// The rows are read-only: the SDK captures those at launch, so an editable
/// field would show a value it never received. Change them in `Secrets.swift`
/// and relaunch. The one control that is editable describes the paypoint rather
/// than the SDK, and says so where it sits.
///
/// The card-not-present rows read from `PayInSharedConfiguration`, the same
/// source the forms use, so this screen cannot drift from the real behaviour.
struct ConfigurationQAView: View {
    @EnvironmentObject private var tokenProbes: TokenProbeResults
    @EnvironmentObject private var demoCustomer: DemoCustomerSetting
    @State private var healthCheckText = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    integrationSection
                    tokenEndpointSection
                    terminalSection
                    cardNotPresentSection
                    diagnosticsSection
                    buildSection
                }
                .padding(16)
            }
            .navigationTitle("Configuration")
        }
    }

    // MARK: - Integration

    private var integrationSection: some View {
        section(
            "Integration",
            note: "The scheme picks the environment; the entry point follows it, from "
                + "`Secrets.entryPoints`. Captured by the SDK at launch."
        ) {
            QADetailRow(
                label: "Entry point",
                value: DemoConfiguration.entryPoint,
                problem: DemoConfiguration.entryPointProblem
            )
            QADetailRow(label: "App ID", value: Secrets.appId)
            QADetailRow(
                label: "Environment",
                value: "\(DemoConfiguration.nameFor(DemoConfiguration.environment)) · " +
                    (DemoConfiguration.environment.baseURL.host ?? "—")
                    + " · " + DemoConfiguration.environmentSource
            )
        }
    }

    // MARK: - Token endpoint

    private var tokenEndpointSection: some View {
        section("Token endpoint", note: "The endpoints the app actually calls, per capability.") {
            // Read from `Secrets` rather than from the local resolver. The two are
            // separate settings that only happen to share a value in this sample,
            // so showing the resolver would diagnose a URL the app never calls on
            // any build that points either endpoint at a real partner backend.
            QADetailRow(
                label: "Card-present",
                value: Secrets.partnerTokenEndpoint.absoluteString
            )
            QADetailRow(
                label: "Card-not-present",
                value: Secrets.partnerPaymentMethodAccessTokenEndpoint.absoluteString
            )
            QADetailRow(
                label: "Local server",
                value: DemoConfiguration.TokenServer.accessTokenURL.absoluteString
            )
            QADetailRow(label: "Resolved by", value: DemoConfiguration.TokenServer.explanation)

            // Both probes live here, outside any step sequence, so either can be
            // re-run at any time. The sequence on a payment tab hides its own
            // probe once the step is done, and a stored method or a captured
            // payment leaves it that way for the rest of the run.
            // One per row, each sized to its label. Side by side the longer
            // label wraps mid-word at this width.
            Button { runTokenCheck() } label: {
                Label("Check card-present token", systemImage: "key.horizontal")
            }
            .buttonStyle(.bordered)
            // `isWorking` is this screen's own. A probe started on a tab is in
            // flight here too, and only the shared answer says so.
            .disabled(isWorking || tokenProbes.isRunning(.cardPresent))

            Button { runCardNotPresentTokenCheck() } label: {
                Label("Check card-not-present tokens", systemImage: "key.horizontal")
            }
            .buttonStyle(.bordered)
            .disabled(
                isWorking
                    || tokenProbes.isRunning(.storedMethod)
                    || tokenProbes.isRunning(.capture)
            )

            Button { runHealthCheck() } label: {
                Label("Local server health", systemImage: "heart.text.square")
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)

            ForEach(
                [
                    tokenProbes.display(for: .cardPresent),
                    tokenProbes.display(for: .storedMethod),
                    tokenProbes.display(for: .capture),
                    healthCheckText
                ].filter { !$0.isEmpty },
                id: \.self
            ) { line in
                Text(line)
                    .font(.caption)
                    .foregroundColor(.payabliOnSurfaceVariant)
            }
        }
    }

    // MARK: - Terminal

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Card present")
                .font(.title3.weight(.semibold))
            TerminalReadinessView(configuredAppId: Secrets.appId)

            Toggle("Send a demo customer", isOn: $demoCustomer.suppliesDemoCustomer)
                .font(.subheadline)
            Text(
                demoCustomer.suppliesDemoCustomer
                    ? "Charging sends \(DemoCustomerSetting.demoCustomerSummary). "
                    + "A paypoint with custom identifiers rejects a sale that names nobody."
                    : "Charging names nobody, for a paypoint with no custom identifiers, and "
                    + "records no customer. A paypoint that has them rejects the sale."
            )
            .font(.caption)
            .foregroundColor(.payabliOnSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Card not present

    private var cardNotPresentSection: some View {
        section("Card not present", note: "Shared by the Method and Capture tabs.") {
            QADetailRow(
                label: "Allowed methods",
                value: PayInSharedConfiguration.allowedMethods
                    .map(\.rawValue).joined(separator: ", ")
            )
            QADetailRow(
                label: "Default method",
                value: PayInSharedConfiguration.defaultMethod.rawValue
            )
            QADetailRow(
                label: "Card fields",
                value: PayInSharedConfiguration.cardFieldOrder
                    .map(\.rawValue).joined(separator: ", ")
            )
            QADetailRow(
                label: "ACH fields",
                value: PayInSharedConfiguration.achFieldOrder
                    .map(\.rawValue).joined(separator: ", ")
            )
            QADetailRow(
                label: "Label layout",
                value: "\(PayInSharedConfiguration.labelLayout)"
                    + ", labels \(PayInSharedConfiguration.showsFieldLabels ? "shown" : "hidden")"
            )
            QADetailRow(
                label: "Formatting",
                value: "card spaces "
                    + (PayInSharedConfiguration.formatting.insertsCardNumberSpaces ? "on" : "off")
                    + ", ACH masking "
                    + (PayInSharedConfiguration.formatting.masksACHAccountEntry ? "on" : "off")
            )

            Toggle("Send a customer number", isOn: $demoCustomer.suppliesPayInCustomer)
                .font(.subheadline)
            Text(
                demoCustomer.suppliesPayInCustomer
                    ? "Capturing sends \(DemoCustomerSetting.payInCustomerSummary), so every payment "
                    + "from this device lands on one customer."
                    : "Capturing sends the name and email typed into the form and no customer number, so "
                    + "the paypoint has nothing to match on and files a new customer for every payment."
            )
            .font(.caption)
            .foregroundColor(.payabliOnSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        section("Diagnostics", note: "Redacted request/response logging in the PayIn tabs.") {
            QADetailRow(
                label: "Stored method",
                value: Secrets.paymentMethodDiagnosticsEnabled ? "on" : "off"
            )
            QADetailRow(
                label: "Capture",
                value: Secrets.paymentCaptureDiagnosticsEnabled ? "on" : "off"
            )
        }
    }

    // MARK: - Build

    private var buildSection: some View {
        section("Build", note: nil) {
            QADetailRow(
                label: "Bundle ID",
                value: Bundle.main.bundleIdentifier ?? "—"
            )
            QADetailRow(
                label: "Signing team",
                value: TapToPayPreflight.resolvedTeamIdentifier
                    ?? "— (no embedded provisioning profile)"
            )
            QADetailRow(label: "Device", value: TapToPayPreflight.machineIdentifier)
            QADetailRow(
                label: "Host",
                value: TapToPayPreflight.runtimeEnvironment.label
            )
            QADetailRow(
                label: "SDK linkage",
                value: "\(DemoConfiguration.Linkage.current)\n"
                    + "(\(DemoConfiguration.Linkage.explanation))"
            )
            QADetailRow(label: "SDK version", value: PayabliCore.version)
        }
    }

    // MARK: - Chrome

    private func section(
        _ title: String,
        note: String?,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.payabliOnSurfaceVariant)
            }
            content()
        }
    }

    // MARK: - Actions

    private func runTokenCheck() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            await tokenProbes.probeCardPresent()
        }
    }

    /// Both card-not-present endpoints, because the two tabs submit with
    /// different token functions and this screen answers for both.
    private func runCardNotPresentTokenCheck() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            await tokenProbes.probeStoredMethod()
            await tokenProbes.probeCapture()
        }
    }

    private func runHealthCheck() {
        isWorking = true
        healthCheckText = "Checking health…"
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let (body, response) = try await URLSession.shared.data(
                    from: DemoConfiguration.TokenServer.healthURL
                )
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else {
                    healthCheckText = "✗ Local token server returned HTTP \(code)"
                    return
                }
                healthCheckText = TokenServerHealth(body: body).report(
                    appHost: DemoConfiguration.environment.baseURL.host,
                    appEntryPoint: DemoConfiguration.entryPoint
                )
            } catch {
                healthCheckText = "✗ Local token server unreachable: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ConfigurationQAView()
        .environmentObject(TokenProbeResults.inert())
        .environmentObject(DemoCustomerSetting())
}
