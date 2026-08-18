import os
import PayabliSDKCore
import PayabliSDKPayInPaymentFlow
import SwiftUI

struct PaymentCaptureQAView: View {
    @ObservedObject var paymentFlow: PayabliPayInPaymentFlow

    @StateObject private var diagnosticsStore = DiagnosticsStore.paymentCapture
    @EnvironmentObject private var tokenProbes: TokenProbeResults
    @EnvironmentObject private var demoCustomer: DemoCustomerSetting
    @State private var resultText = ""
    @State private var resultAcknowledged = false
    @State private var submitFailed = false
    @State private var capturedResult: PayabliPayInPaymentFlowResult?
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

                            PayabliPayInPaymentFlowView(
                                component: paymentFlow,
                                configuration: configuration,
                                onCompleted: handlePaymentCaptured,
                                onError: handleError
                            )
                            .payabliPayInPaymentFlowStyle(style)

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
            .navigationDestination(isPresented: $isPaymentCaptureResultViewPresented) {
                if let capturedResult {
                    PaymentCaptureResultView(result: capturedResult)
                }
            }
        }
        .payabliPayInPaymentFlowSheet(
            isPresented: $isPaymentCaptureSheetPresented,
            component: paymentFlow,
            configuration: configuration,
            sheetConfiguration: PayabliPayInPaymentFlowSheetConfiguration(
                title: "Submit Payment",
                dismissButton: .back
            ),
            style: style,
            onCompleted: handlePaymentCaptured,
            onError: handleError
        )
        // The request is built when the app launches and the switch is on another tab,
        // so a flip after that would otherwise apply to the payment after this one.
        // Not while a submission is in flight: replacing the configuration then loses
        // the key that makes its retry safe.
        .onChange(of: demoCustomer.suppliesPayInCustomer) { _ in
            guard !paymentFlow.isSubmitting else { return }
            paymentFlow.configure(requestConfiguration: nextRequest())
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
        QADetailRow(
            label: "Total",
            value: formattedTotal(paymentFlow.requestConfiguration?.paymentDetails)
        )
    }

    /// The currency comes from the same payment details as the figure, so the
    /// two cannot disagree, and the reader's own locale decides the grouping and
    /// the decimal mark.
    private func formattedTotal(_ details: PayabliPayInPaymentFlowPaymentDetails?) -> String {
        guard let details else { return "-" }
        return details.totalAmount.formatted(.currency(code: details.currency ?? "USD"))
    }

    // MARK: - The sequence

    /// `PayabliPayInPaymentFlow` publishes only `isSubmitting` and `lastResult`,
    /// so the sequence derives from those plus the token probe.
    private var steps: PayInFlowSteps {
        PayInSteps.forCapture(
            PayInProgress(
                tokenCheck: tokenProbes.check(.capture),
                hasResult: paymentFlow.lastResult != nil,
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
        paymentFlow.configure(requestConfiguration: nextRequest())
    }

    /// The next attempt: a fresh amount, a fresh key, and whatever the switch says now.
    private func nextRequest() -> PayabliPayInPaymentFlowRequestConfiguration {
        Self.freshRequestConfiguration(suppliesCustomer: demoCustomer.suppliesPayInCustomer)
    }

    /// A capture's request configuration, with a key minted per submission.
    ///
    /// The app builds one of these at launch for the initial submit. Reusing that
    /// key for a second capture would send two distinct payments under one
    /// idempotency key, which the API may deduplicate or reject.
    ///
    /// The amount is drawn per attempt and the identifiers name this device and the
    /// moment, so a run over several devices at once produces rows a dashboard can
    /// attribute. The form collects no amount and no customer number, so both are
    /// decided here.
    ///
    /// - Parameter suppliesCustomer: whether the request names the customer, which
    ///   ``DemoCustomerSetting`` decides. A value the payer types wins over this
    ///   one; the form has no such box.
    static func freshRequestConfiguration(
        suppliesCustomer: Bool
    ) -> PayabliPayInPaymentFlowRequestConfiguration {
        let identity = QAIdentity.current
        return PayabliPayInPaymentFlowRequestConfiguration(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
                totalAmount: QAAmount.random(),
                serviceFee: 0.10,
                currency: "USD"
            ),
            customerData: suppliesCustomer ? DemoCustomerSetting.payInCustomer : nil,
            orderDescription: identity.note("capture"),
            orderId: identity.orderId(at: Date()),
            source: "ios-payment-capture-qa",
            idempotencyKey: UUID().uuidString,
            achValidation: true,
            forceCustomerCreation: true
        )
    }

    private func runTokenCheck() {
        Task { await tokenProbes.probeCapture() }
    }

    private var configuration: PayabliPayInPaymentFlowFormConfiguration {
        PayabliPayInPaymentFlowFormConfiguration(
            allowedMethods: PayInSharedConfiguration.allowedMethods,
            defaultMethod: PayInSharedConfiguration.defaultMethod,
            cardFieldOrder: PayInSharedConfiguration.cardFieldOrder,
            achFieldOrder: PayInSharedConfiguration.achFieldOrder,
            cardSections: [
                PayabliPayInPaymentFlowFieldSection(
                    title: "Card Information",
                    titleStyle: PayabliPayInPaymentFlowTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .cardholderName,
                        .cardNumber,
                        .cardExpiration,
                        .cardCvv,
                        .cardZip
                    ]
                ),
                PayabliPayInPaymentFlowFieldSection(
                    title: "Customer Information",
                    titleStyle: PayabliPayInPaymentFlowTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .firstName,
                        .lastName,
                        .billingEmail
                    ]
                ),
                PayabliPayInPaymentFlowFieldSection(
                    title: "Payment Information",
                    titleStyle: PayabliPayInPaymentFlowTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .amount,
                        .serviceFee
                    ]
                )
            ],
            achSections: [
                PayabliPayInPaymentFlowFieldSection(
                    title: "Bank Information",
                    titleStyle: PayabliPayInPaymentFlowTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .achHolder,
                        .achRouting,
                        .achAccount,
                        .achAccountType
                    ]
                ),
                PayabliPayInPaymentFlowFieldSection(
                    title: "Customer Information",
                    titleStyle: PayabliPayInPaymentFlowTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .firstName,
                        .lastName,
                        .billingEmail
                    ]
                ),
                PayabliPayInPaymentFlowFieldSection(
                    title: "Payment Information",
                    titleStyle: PayabliPayInPaymentFlowTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .amount,
                        .serviceFee
                    ]
                )
            ],
            hiddenValues: PayabliPayInPaymentFlowHiddenValues(
                achHolderType: .personal,
                achSecCode: .web,
                // What a transaction list shows as the note, and what names the device that sent it. Here
                // rather than only on the request configuration because this value wins over that one: the
                // component merges the form's description over the request's before it sends.
                methodDescription: QAIdentity.current.note("capture")
            ),
            labels: PayabliPayInPaymentFlowLabels(
                title: "Payment Capture",
                subtitle: "Submit a card or ACH payment.",
                submitButton: "Submit Payment",
                fieldPlaceholders: labelMatchingPlaceholders(for: fieldsWithHiddenLabels)
            ),
            labelLayout: PayInSharedConfiguration.labelLayout,
            showsFieldLabels: PayInSharedConfiguration.showsFieldLabels,
            hiddenFieldLabels: Set(fieldsWithHiddenLabels),
            formatting: PayInSharedConfiguration.formatting,
            inputSizing: PayInSharedConfiguration.inputSizing,
            cardBrandIconPlacement: PayInSharedConfiguration.cardBrandIconPlacement,
            paymentSummary: PayabliPayInPaymentFlowPaymentSummaryConfiguration(
                labelStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle(
                    font: .subheadline,
                    color: .secondary
                ),
                valueStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle(
                    font: .subheadline.weight(.semibold),
                    color: .primary
                ),
                rowSpacing: 6
            )
        )
    }

    private var style: PayabliPayInPaymentFlowStyle {
        PayInSharedConfiguration.style
    }

    private var fieldsWithHiddenLabels: [PayabliPayInPaymentFlowField] {
        PayInSharedConfiguration.fieldsWithHiddenLabels
    }

    private func labelMatchingPlaceholders(
        for fields: [PayabliPayInPaymentFlowField]
    ) -> [PayabliPayInPaymentFlowField: String] {
        PayInSharedConfiguration.labelMatchingPlaceholders(for: fields)
    }

    private func handlePaymentCaptured(_ result: PayabliPayInPaymentFlowResult) {
        resultAcknowledged = false
        submitFailed = false
        capturedResult = result
        resultText = [
            "Code: \(result.code)",
            "Reason: \(result.reason ?? "-")",
            "Payment trans ID: \(result.transaction?.paymentTransId ?? "-")",
            "Gateway trans ID: \(result.transaction?.gatewayTransId ?? "-")",
            "Method: \(result.transaction?.method ?? "-")",
            "Operation: \(result.transaction?.operation ?? "-")"
        ].joined(separator: "\n")
        Logger(
            subsystem: "com.payabli.example.app",
            category: "PaymentCaptureDiagnostics"
        ).info("Payment captured: \(result.code, privacy: .public)")

        if isPaymentCaptureSheetPresented {
            isPaymentCaptureSheetPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isPaymentCaptureResultViewPresented = true
            }
        } else {
            isPaymentCaptureResultViewPresented = true
        }
    }

    private func handleError(_ error: Error) {
        submitFailed = true
        // An idempotency key is spent once submitted, and a failed form stays
        // retryable, so the retry needs a key of its own to be a payment rather
        // than a duplicate. A failed form blocks the result row, so this is the
        // only place one can be minted.
        paymentFlow.configure(requestConfiguration: nextRequest())
        let message = paymentCaptureErrorMessage(error)
        resultText = "Payment capture failed: \(message)"
        Logger(
            subsystem: "com.payabli.example.app",
            category: "PaymentCaptureDiagnostics"
        ).error("Payment capture failed: \(message, privacy: .public)")
    }

    private func paymentCaptureErrorMessage(_ error: Error) -> String {
        if isDuplicateSubmission(error) {
            return "Duplicate submission (409): the attempt before this one used the same "
                + "idempotency key. A new key is set, so submitting again sends a new payment."
        }
        if let payabliError = error as? any PayabliError {
            if let detail = payabliError.detail, !detail.isEmpty, detail != payabliError.reason {
                return "\(payabliError.reason)\n\(detail)"
            }
            return payabliError.reason
        }
        return String(describing: error)
    }

    /// `mapPayabliHTTPError` has no 409 case, so a duplicate arrives through the
    /// default branch as the bare reason `HTTP 409`, which names a status and no
    /// cause. The typed failure carries the code where the API answered with a
    /// body; the generic error is what an empty one becomes.
    private func isDuplicateSubmission(_ error: Error) -> Bool {
        if case let PayabliPayInPaymentFlowError.transactionFailed(failure) = error,
           failure.httpStatusCode == 409
        {
            return true
        }
        if let payabliError = error as? any PayabliError, payabliError.reason.contains("409") {
            return true
        }
        return false
    }
}

#Preview {
    PaymentCaptureQAView(
        paymentFlow: PayabliPayInPaymentFlow(
            accessToken: "preview-token",
            entryPoint: "preview-entry",
            environment: DemoConfiguration.environment,
            operation: .capture,
            requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration(
                paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
                    totalAmount: 1,
                    serviceFee: 0.10,
                    currency: "USD"
                ),
                orderDescription: "Preview Payment",
                orderId: "preview-order",
                source: "preview",
                idempotencyKey: "preview-key"
            )
        )
    )
    .environmentObject(TokenProbeResults.inert())
}
