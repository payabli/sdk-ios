import Dispatch
import os
import PayabliSDKPayInPaymentFlow
import SwiftUI

struct PaymentMethodQAView: View {
    @ObservedObject var paymentFlow: PayabliPayInPaymentFlow

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

                            PayabliPayInPaymentFlowView(
                                component: paymentFlow,
                                configuration: configuration,
                                onCompleted: handlePaymentMethodAdded,
                                onError: handleError
                            )
                            .payabliPayInPaymentFlowStyle(style)

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
            .navigationDestination(isPresented: $isPaymentMethodAddedViewPresented) {
                PaymentMethodAddedView()
            }
        }
        .payabliPayInPaymentFlowSheet(
            isPresented: $isPaymentMethodSheetPresented,
            component: paymentFlow,
            configuration: configuration,
            sheetConfiguration: PayabliPayInPaymentFlowSheetConfiguration(
                title: "Add Payment Method",
                dismissButton: .back
            ),
            style: style,
            onCompleted: handlePaymentMethodAdded,
            onError: handleError
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

    /// `PayabliPayInPaymentFlow` publishes only `isSubmitting` and `lastResult`,
    /// so the sequence derives from those plus the token probe.
    private var steps: PayInFlowSteps {
        PayInSteps.forStoringMethod(
            PayInProgress(
                tokenCheck: tokenProbes.check(.storedMethod),
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
    }

    private func runTokenCheck() {
        Task { await tokenProbes.probeStoredMethod() }
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
                        // A stored method belongs to a customer, and the number is what a later
                        // charge finds it by. The capture form leaves it out for the opposite
                        // reason: nothing is being stored against a customer there.
                        .customerNumber,
                        .billingEmail
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
                        // A stored method belongs to a customer, and the number is what a later
                        // charge finds it by. The capture form leaves it out for the opposite
                        // reason: nothing is being stored against a customer there.
                        .customerNumber,
                        .billingEmail
                    ]
                )
            ],
            hiddenValues: PayabliPayInPaymentFlowHiddenValues(
                achHolderType: .personal,
                achSecCode: .web,
                methodDescription: QAIdentity.current.note("save")
            ),
            options: PayabliPayInPaymentFlowOptions(
                // Off, as the Android sample's store options are, so a published
                // test routing and account pair can be stored. An integrator
                // holding an account that validates turns it on.
                achValidation: false,
                createAnonymous: false,
                forceCustomerCreation: true,
                temporary: false,
                source: "ios-payment-method-qa"
            ),
            labels: PayabliPayInPaymentFlowLabels(
                title: "Save Payment Method",
                subtitle: "Create a card or ACH token.",
                fieldPlaceholders: labelMatchingPlaceholders(for: fieldsWithHiddenLabels)
            ),
            labelLayout: PayInSharedConfiguration.labelLayout,
            showsFieldLabels: PayInSharedConfiguration.showsFieldLabels,
            hiddenFieldLabels: Set(fieldsWithHiddenLabels),
            formatting: PayInSharedConfiguration.formatting,
            inputSizing: PayInSharedConfiguration.inputSizing,
            cardBrandIconPlacement: PayInSharedConfiguration.cardBrandIconPlacement
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

    private func handlePaymentMethodAdded(_ result: PayabliPayInPaymentFlowResult) {
        resultAcknowledged = false
        submitFailed = false
        guard let method = result.storedPaymentMethod else {
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
        ).info("Payment method added: \(method.responseText, privacy: .public)")

        if isPaymentMethodSheetPresented {
            isPaymentMethodSheetPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isPaymentMethodAddedViewPresented = true
            }
        } else {
            isPaymentMethodAddedViewPresented = true
        }
    }

    private func handleError(_ error: Error) {
        submitFailed = true
        resultText = "Payment method failed: \(error.localizedDescription)"
        Logger(
            subsystem: "com.payabli.example.app",
            category: "PaymentMethodDiagnostics"
        ).error("Payment method failed: \(error.localizedDescription, privacy: .public)")
    }
}

#Preview {
    PaymentMethodQAView(
        paymentFlow: PayabliPayInPaymentFlow(
            accessToken: "preview-token",
            entryPoint: "preview-entry",
            environment: DemoConfiguration.environment
        )
    )
    .environmentObject(TokenProbeResults.inert())
}
