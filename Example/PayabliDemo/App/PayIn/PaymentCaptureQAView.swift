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
    @State private var voidedTransId: String?
    @State private var startedAReversal = false
    @State private var unreconciled: [String] = []
    @State private var voidText = ""

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
                            // The flow refuses a new attempt while a reversal is on its way, and
                            // this says so rather than letting the press do nothing.
                            .disabled(paymentFlow.isSubmitting)

                            // Only a payment that reported an identifier can be reversed, and
                            // only once: the service refuses the second attempt, and offering a
                            // button for a refusal teaches the wrong thing.
                            if let transId = capturedResult?.reversibleTransId {
                                Button { reverse(transId) } label: {
                                    Label(
                                        voidedTransId == transId ? "Reversed" : "Reverse this payment",
                                        systemImage: "arrow.uturn.backward"
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                // The flow's own flag rather than a copy of it: it is the
                                // exclusion the flow enforces made observable, so a control cannot
                                // disagree with the thing doing the refusing.
                                .disabled(
                                    voidedTransId == transId
                                        || unreconciled.contains(transId)
                                        || paymentFlow.isSubmitting
                                )

                                if !voidText.isEmpty {
                                    Text(voidText)
                                        .font(.caption)
                                        .foregroundColor(
                                            voidedTransId == transId ? .payabliOnSurfaceVariant : .payabliError
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    // Outside the steps, not merely outside the payment's row. A step hides its
                    // own content once it is blocked, so a later capture failure would take this
                    // down with it, and what it names is the one thing needed to reconcile money
                    // that may already have moved.
                    if !unreconciled.isEmpty {
                        Text(
                            "A reversal of \(unreconciled.joined(separator: ", ")) may have been "
                                + "applied. Read back before reversing again."
                        )
                        .font(.caption)
                        .foregroundColor(.payabliError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
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
                // A capture in flight, not a submission in flight. The flow's flag answers
                // whether the next call would be refused, which is true of the reversal this
                // screen started too, and the capture steps would then hide the payment being
                // reversed and offer the form again underneath it.
                isSubmitting: paymentFlow.isSubmitting && !startedAReversal,
                submitFailed: submitFailed
            )
        )
    }

    /// Abandons the attempt on screen and draws another. This is the one action
    /// here that may charge a second time: submitting again retries the attempt
    /// that already has a key, and this mints a new one.
    private func startAnother() {
        // The flow refuses while a submission is in flight, and this row keeps
        // offering the button through one. Clearing first would report an attempt
        // that was never drawn, over a request still holding the earlier key.
        guard paymentFlow.startNewAttempt(suppliesCustomer: demoCustomer.suppliesPayInCustomer) else {
            return
        }
        resultAcknowledged = true
        submitFailed = false
        resultText = ""
        capturedResult = nil
        voidedTransId = nil
        voidText = ""
    }

    /// Reverses the payment on screen.
    ///
    /// The identifier comes from the result the flow reported, so nothing here builds a
    /// request or holds a key. A refusal is shown as the service worded it.
    private func reverse(_ transId: String) {
        // The flow refuses a second submission itself. Asking first keeps a queued tap from
        // becoming a call whose refusal would read as this reversal's answer.
        guard !paymentFlow.isSubmitting else { return }
        voidText = ""
        startedAReversal = true
        Task {
            defer { startedAReversal = false }
            do {
                let outcome = try await paymentFlow.voidTransaction(transId)
                Logger(
                    subsystem: "com.payabli.example.app",
                    category: "PaymentCaptureDiagnostics"
                ).info("Payment reversed: \(outcome.code, privacy: .public)")
                voidedTransId = transId
                unreconciled.removeAll { $0 == transId }
                show("Reversed. Code: \(outcome.code) Reason: \(outcome.reason ?? "-")", for: transId)
            } catch {
                let failure = PayInFailure(error, operation: .void)
                // Only this transaction's question is answered here. A settled failure for one
                // reversal says nothing about another that is still open.
                if failure.outcomeIsUnresolved {
                    if !unreconciled.contains(transId) {
                        unreconciled.append(transId)
                    }
                } else {
                    unreconciled.removeAll { $0 == transId }
                }
                guard !failure.refusedForAnotherSubmission else { return }
                show(failure.message, for: transId)
            }
        }
    }

    /// Shows what a reversal answered, if the payment it answers about is still on screen.
    ///
    /// The transaction comes from the call's own scope rather than from anything stored, so an
    /// answer cannot be matched to the wrong request or dropped because an unrelated one finished
    /// first.
    private func show(_ text: String, for transId: String) {
        guard capturedResult?.reversibleTransId == transId else { return }
        voidText = text
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
        // Nothing was submitted, so nothing about this capture failed. Recording it would replace
        // the payment on screen with an error and leave the result blocked behind it, and the way
        // back from that clears what a reversal had already reported.
        guard !failure.refusedForAnotherSubmission else { return }
        submitFailed = true
        // A refused card and a lost response no longer read alike: the first
        // arrives as a transaction the service declined, the second as an
        // interruption saying the payment may already have been taken. Only the
        // second needs reconciling, and reconciling means reading the earlier
        // submission back. Submitting again sends this attempt's own key, which
        // the service refuses for two minutes from the first request and executes
        // after that, so a late resubmission is a second payment.
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
