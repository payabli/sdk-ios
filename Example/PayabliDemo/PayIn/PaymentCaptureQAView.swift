import os
import SwiftUI

struct PaymentCaptureQAView: View {
    @ObservedObject var paymentFlow: PayInFlowHandle

    @StateObject private var diagnosticsStore = DiagnosticsStore.paymentCapture
    @EnvironmentObject private var tokenProbes: TokenProbeResults
    @EnvironmentObject private var demoCustomer: DemoCustomerSetting
    @State private var resultText = ""
    @State private var resultAcknowledged = false
    @State private var submitFailed = false
    @State private var capturedResult: PayInOutcome?
    @State private var isPaymentCaptureSheetPresented = false
    @State private var isPaymentCaptureResultViewPresented = false

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
                            .disabled(tokenProbes.isRunning(.capture))
                            if !tokenProbes.display(for: .capture).isEmpty {
                                Text(tokenProbes.display(for: .capture))
                                    .font(.caption)
                                    .foregroundColor(tokenProbes.display(for: .capture)
                                        .hasPrefix("✗") ? .payabliError : .payabliOnSurfaceVariant)
                            }
                        }
                    }

                    StepRow(index: 2, step: steps.form) {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                isPaymentCaptureSheetPresented = true
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
                                form: PayInForms.capture,
                                onCompleted: handlePaymentCaptured,
                                onFailed: handleError
                            )

                            totalRow

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

                                // Submitting again retries this payment. This
                                // abandons it and draws another, which is the
                                // one action that may charge a second time.
                                Button { startAnother() } label: {
                                    Label("Start a new attempt", systemImage: "arrow.counterclockwise")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    StepRow(index: 3, step: steps.result) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(resultText.isEmpty ? "Nothing captured yet." : resultText)
                                .font(.footnote)
                                .foregroundColor(.payabliOnSurfaceVariant)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)

                            Button { startAnother() } label: {
                                Label("Capture another payment", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    DiagnosticsSection(store: diagnosticsStore, isEnabled: Secrets.paymentCaptureDiagnosticsEnabled)
                }
                .padding(16)
            }
            .navigationTitle("Capture a payment")
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(isPresented: $isPaymentCaptureResultViewPresented) {
                if let capturedResult {
                    PaymentCaptureResultView(outcome: capturedResult)
                }
            }
        }
        .paymentFormSheet(
            isPresented: $isPaymentCaptureSheetPresented,
            flow: paymentFlow,
            form: PayInForms.capture,
            title: "Submit Payment",
            onCompleted: handlePaymentCaptured,
            onFailed: handleError
        )
        // The request is built when the app launches and the switch is on another tab,
        // so a flip after that would otherwise apply to the payment after this one.
        // Not while a submission is in flight: replacing the configuration then loses
        // the key that makes its retry safe. Only the customer changes, so the figure
        // on screen and the identifiers stay as they were.
        .onChange(of: demoCustomer.suppliesPayInCustomer) { supplies in
            paymentFlow.applyCustomerChange(suppliesCustomer: supplies)
        }
        #if DEBUG
        .onChange(of: isPaymentCaptureSheetPresented) { isPresented in
                guard isPresented else { return }
                // Let the sheet's fields mount before injecting values.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    DebugPrefill.fill()
                }
            }
        #endif
    }

    /// What the request charges, which the form's own summary does not show.
    ///
    /// The summary reads back an amount and a service fee and never their sum, so the figure that leaves the
    /// payer's account appears nowhere before submitting. The SDK renders the fields it knows and a total is not
    /// one of them, so showing it there would mean widening a public enum for the sample app's benefit.
    ///
    /// No arithmetic at submission: `totalAmount` is what the request already carries and the fee is part of it,
    /// so this reads that one value off the component rather than adding the rows up on screen.
    private var totalRow: some View {
        QADetailRow(label: "Total", value: paymentFlow.formattedTotal)
    }

    // MARK: - The sequence

    /// The flow answers only whether it is submitting and whether it holds a
    /// result, so the sequence derives from those plus the token probe.
    private var steps: PayInFlowSteps {
        PayInSteps.forCapture(
            PayInProgress(
                tokenCheck: tokenProbes.check(.capture),
                hasResult: paymentFlow.hasResult,
                resultAcknowledged: resultAcknowledged,
                isSubmitting: paymentFlow.isSubmitting,
                submitFailed: submitFailed
            )
        )
    }

    /// Abandons the attempt on screen and draws another. This is the one action
    /// here that may charge a second time: submitting again retries the attempt
    /// that already has a key, and this mints a new one.
    private func startAnother() {
        resultAcknowledged = true
        submitFailed = false
        resultText = ""
        paymentFlow.startNewAttempt(suppliesCustomer: demoCustomer.suppliesPayInCustomer)
    }

    private func runTokenCheck() {
        Task { await tokenProbes.probeCapture() }
    }

    private func handlePaymentCaptured(_ outcome: PayInOutcome) {
        resultAcknowledged = false
        submitFailed = false
        capturedResult = outcome
        resultText = [
            "Code: \(outcome.code)",
            "Reason: \(outcome.reason ?? "-")",
            "Payment trans ID: \(outcome.transaction?.paymentTransId ?? "-")",
            "Gateway trans ID: \(outcome.transaction?.gatewayTransId ?? "-")",
            "Method: \(outcome.transaction?.method ?? "-")",
            "Operation: \(outcome.transaction?.operation ?? "-")"
        ].joined(separator: "\n")
        Logger(
            subsystem: "com.payabli.example.app",
            category: "PaymentCaptureDiagnostics"
        ).info("Payment captured: \(outcome.code, privacy: .public)")

        if isPaymentCaptureSheetPresented {
            isPaymentCaptureSheetPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isPaymentCaptureResultViewPresented = true
            }
        } else {
            isPaymentCaptureResultViewPresented = true
        }
    }

    private func handleError(_ failure: PayInFailure) {
        submitFailed = true
        // The request keeps its idempotency key. A failure does not say whether
        // the service accepted the payment: a lost response and a refused card
        // arrive the same way, and a submit carrying the same key is answered
        // from the attempt that already reached it.
        //
        // Drawing a fresh attempt is the button beside this message, and it is
        // the only place a key is minted.
        resultText = "Payment capture failed: \(failure.message)"
        Logger(
            subsystem: "com.payabli.example.app",
            category: "PaymentCaptureDiagnostics"
        ).error("Payment capture failed: \(failure.logLabel, privacy: .public)")
    }
}

#Preview {
    PaymentCaptureQAView(paymentFlow: PayInSessions.preview(capturing: true))
        .environmentObject(TokenProbeResults.inert())
        .environmentObject(DemoCustomerSetting())
}
