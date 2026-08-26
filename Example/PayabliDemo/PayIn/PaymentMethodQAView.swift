import Dispatch
import os
import SwiftUI

struct PaymentMethodQAView: View {
    @ObservedObject var paymentFlow: PayInFlowHandle

    @StateObject private var diagnosticsStore = DiagnosticsStore.paymentMethod
    @EnvironmentObject private var tokenProbes: TokenProbeResults
    @State private var resultText = ""
    @State private var resultAcknowledged = false
    @State private var submitFailed = false
    @State private var isPaymentMethodAddedViewPresented = false
    @State private var isPaymentMethodSheetPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    QAContextLine()

                    Text("Steps")
                        .font(.headline)

                    StepRow(index: 1, step: steps.backend) {
                        VStack(alignment: .leading, spacing: 6) {
                            Button { runTokenCheck() } label: {
                                Label("Check token endpoint", systemImage: "key.horizontal")
                            }
                            .buttonStyle(.bordered)
                            // The probe is shared, so a run started on another
                            // tab is in flight here too. The store is what knows
                            // that; a local flag does not.
                            .disabled(tokenProbes.isRunning(.storedMethod))
                            if !tokenProbes.display(for: .storedMethod).isEmpty {
                                Text(tokenProbes.display(for: .storedMethod))
                                    .font(.caption)
                                    .foregroundColor(tokenProbes.display(for: .storedMethod)
                                        .hasPrefix("✗") ? .payabliError : .payabliOnSurfaceVariant)
                            }
                        }
                    }

                    StepRow(index: 2, step: steps.form) {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                isPaymentMethodSheetPresented = true
                            } label: {
                                Label("Open as a sheet instead", systemImage: "rectangle.bottomthird.inset.filled")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            #if DEBUG
                                DebugPrefillButton()
                            #endif

                            PaymentFormHost(
                                flow: paymentFlow,
                                form: PayInForms.storedMethod,
                                onCompleted: handlePaymentMethodAdded,
                                onFailed: handleError
                            )

                            // The step that failed shows why. A failed form
                            // blocks the result row, which is the only other
                            // place this text renders, so leaving it there
                            // offers a retry with no reason beside it.
                            if submitFailed {
                                Text(resultText)
                                    .font(.footnote)
                                    .foregroundColor(.payabliError)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    StepRow(index: 3, step: steps.result) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(resultText.isEmpty ? "Nothing stored yet." : resultText)
                                .font(.footnote)
                                .foregroundColor(.payabliOnSurfaceVariant)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)

                            Button { startAnother() } label: {
                                Label("Save another method", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    DiagnosticsSection(store: diagnosticsStore, isEnabled: Secrets.paymentMethodDiagnosticsEnabled)
                }
                .padding(16)
            }
            .navigationTitle("Save a method")
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(isPresented: $isPaymentMethodAddedViewPresented) {
                PaymentMethodAddedView()
            }
        }
        .paymentFormSheet(
            isPresented: $isPaymentMethodSheetPresented,
            flow: paymentFlow,
            form: PayInForms.storedMethod,
            title: "Add Payment Method",
            onCompleted: handlePaymentMethodAdded,
            onFailed: handleError
        )
        #if DEBUG
        .onChange(of: isPaymentMethodSheetPresented) { isPresented in
                guard isPresented else { return }
                // Let the sheet's fields mount before injecting values.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    DebugPrefill.fill()
                }
            }
        #endif
    }

    // MARK: - The sequence

    /// The flow answers only whether it is submitting and whether it holds a
    /// result, so the sequence derives from those plus the token probe.
    private var steps: PayInFlowSteps {
        PayInSteps.forStoringMethod(
            PayInProgress(
                tokenCheck: tokenProbes.check(.storedMethod),
                hasResult: paymentFlow.hasResult,
                resultAcknowledged: resultAcknowledged,
                isSubmitting: paymentFlow.isSubmitting,
                submitFailed: submitFailed
            )
        )
    }

    /// Hands the flow back to step 2 for another entry. The component keeps
    /// `lastResult` forever and exposes no reset, so a finished submit would
    /// otherwise pin the sequence on step 3.
    private func startAnother() {
        resultAcknowledged = true
        submitFailed = false
        resultText = ""
    }

    private func runTokenCheck() {
        Task { await tokenProbes.probeStoredMethod() }
    }

    private func handlePaymentMethodAdded(_ outcome: PayInOutcome) {
        resultAcknowledged = false
        submitFailed = false
        guard let method = outcome.storedMethod else {
            resultText = "Payment method response did not include a stored method."
            return
        }

        resultText = [
            "Stored method: \(method.storedMethodId ?? "-")",
            "Response: \(method.responseText)",
            "Result: \(method.resultText ?? "-")"
        ].joined(separator: "\n")
        Logger(
            subsystem: "com.payabli.example.app",
            category: "PaymentMethodDiagnostics"
        ).info("Payment method added: result=\(method.resultCode ?? 0, privacy: .public)")

        if isPaymentMethodSheetPresented {
            isPaymentMethodSheetPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isPaymentMethodAddedViewPresented = true
            }
        } else {
            isPaymentMethodAddedViewPresented = true
        }
    }

    private func handleError(_ failure: PayInFailure) {
        submitFailed = true
        resultText = "Payment method failed: \(failure.message)"
        Logger(
            subsystem: "com.payabli.example.app",
            category: "PaymentMethodDiagnostics"
        ).error("Payment method failed: \(failure.logLabel, privacy: .public)")
    }
}

#Preview {
    PaymentMethodQAView(paymentFlow: PayInSessions.preview())
        .environmentObject(TokenProbeResults.inert())
}
