import PayabliSDKCore
import PayabliSDKPayInPaymentFlow
import SwiftUI

/// Every knob the demo runs on, in one read-only place.
///
/// Read-only on purpose. The three SDK facades are `@StateObject`s built once at
/// launch, so `entryPoint`, `environment` and `appId` cannot be re-read
/// afterwards — an editable field for those would show a value the SDK never
/// received. Edit them in `Secrets.swift` and relaunch.
///
/// The card-not-present rows read from `PayInSharedConfiguration`, the same
/// source the forms use, so this screen cannot drift from the real behaviour.
struct ConfigurationQAView: View {
    @State private var tokenCheckText = ""
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
        section("Integration", note: "Set in `Secrets.swift`; captured by the SDK at launch.") {
            QADetailRow(
                label: "Entry point",
                value: Secrets.entryPoint,
                problem: Secrets.entryPoint.isEmpty
                    ? "Empty — /config is keyed by entry point."
                    : nil
            )
            QADetailRow(label: "App ID", value: Secrets.appId)
            QADetailRow(
                label: "Environment",
                value: "\(environmentName) · " + (DemoConfiguration.environment.baseURL.host ?? "—")
                    + " · " + DemoConfiguration.environmentSource
            )
        }
    }

    /// `PayabliEnvironment` is an `@objc Int` enum, so string interpolation
    /// renders `PayabliEnvironment(rawValue: 1)` rather than the case name.
    private var environmentName: String {
        switch DemoConfiguration.environment {
        case .qa: return "qa"
        case .sandbox: return "sandbox"
        case .production: return "production"
        default: return "other"
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

            HStack(spacing: 12) {
                Button { runTokenCheck() } label: {
                    Label("Check token", systemImage: "key.horizontal")
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)

                Button { runHealthCheck() } label: {
                    Label("Health", systemImage: "heart.text.square")
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }

            ForEach([tokenCheckText, healthCheckText].filter { !$0.isEmpty }, id: \.self) { line in
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

    @ViewBuilder
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

    /// Reports only *that* a token arrived. Never the value.
    private func runTokenCheck() {
        isWorking = true
        tokenCheckText = "Checking token…"
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

    private func runHealthCheck() {
        isWorking = true
        healthCheckText = "Checking health…"
        Task {
            defer { isWorking = false }
            do {
                let (_, response) = try await URLSession.shared.data(
                    from: DemoConfiguration.TokenServer.healthURL
                )
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                healthCheckText = code == 200
                    ? "✓ Local token server healthy"
                    : "✗ Local token server returned HTTP \(code)"
            } catch {
                healthCheckText = "✗ Local token server unreachable: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ConfigurationQAView()
}
