import Dispatch
import os
import PayabliSDKPayInPaymentFlow
import SwiftUI

struct PaymentMethodQAView: View {
    let paymentFlow: PayabliPayInPaymentFlow

    @StateObject private var diagnosticsStore = DiagnosticsStore.paymentMethod
    @State private var resultText = ""
    @State private var tokenCheckText = ""
    @State private var resultAcknowledged = false
    @State private var isCheckingToken = false
    @State private var isPaymentMethodAddedViewPresented = false
    @State private var isPaymentMethodSheetPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    QAContextLine()

                    Text("Steps")
                        .font(.headline)

                    QAStepRow(
                        index: 1,
                        title: "Reach the token backend",
                        detail: "The SDK asks your backend for a short-lived access token before it submits.",
                        status: tokenStepStatus
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            Button { runTokenCheck() } label: {
                                Label("Check token endpoint", systemImage: "key.horizontal")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isCheckingToken)
                            if !tokenCheckText.isEmpty {
                                Text(tokenCheckText)
                                    .font(.caption)
                                    .foregroundColor(tokenCheckText.hasPrefix("✗") ? .payabliError : .payabliOnSurfaceVariant)
                            }
                        }
                    }

                    QAStepRow(
                        index: 2,
                        title: "Enter the card or ACH details",
                        detail: "The SDK owns these fields; clear PAN never reaches the host app.",
                        status: formStepStatus
                    ) {
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
                        }
                    }

                    QAStepRow(
                        index: 3,
                        title: "Stored method",
                        detail: "A successful submit returns a reusable stored-method id.",
                        status: resultStepStatus
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(resultText.isEmpty ? "Nothing stored yet." : resultText)
                                .font(.footnote)
                                .foregroundColor(resultText.hasPrefix("✗") ? .payabliError : .payabliOnSurfaceVariant)
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

    // MARK: - Step status

    /// `PayabliPayInPaymentFlow` publishes only `isSubmitting` and `lastResult`,
    /// so these three derive from those plus the token check — never from state
    /// tracked separately, which could disagree with the component.
    /// True once the backend is known reachable — either the check was run, or
    /// a submit already succeeded, which proves it just as well.
    private var backendProven: Bool {
        tokenCheckText.hasPrefix("✓") || paymentFlow.lastResult != nil
    }

    /// The component keeps `lastResult` forever and exposes no reset, so a
    /// finished submit would pin the flow on step 3 with no way back. This
    /// records that the result has been read and another entry is wanted.
    private var showingFinishedResult: Bool {
        paymentFlow.lastResult != nil && !resultAcknowledged
    }

    /// Hands the flow back to step 2 for another entry.
    private func startAnother() {
        resultAcknowledged = true
        resultText = ""
    }

    private var tokenStepStatus: QAStepStatus {
        if tokenCheckText.hasPrefix("✗") { return .failed }
        return backendProven ? .done : .current
    }

    private var formStepStatus: QAStepStatus {
        // Exactly one step is ever `.current`, so this waits rather than
        // competing with step 1 for attention.
        guard backendProven else { return .blocked }
        if paymentFlow.isSubmitting { return .inProgress }
        if resultText.hasPrefix("✗") { return .failed }
        return showingFinishedResult ? .done : .current
    }

    private var resultStepStatus: QAStepStatus {
        if resultText.hasPrefix("✗") { return .failed }
        return showingFinishedResult ? .current : .blocked
    }

    /// Reports only that a token arrived. Never the token itself.
    private func runTokenCheck() {
        isCheckingToken = true
        tokenCheckText = "Checking…"
        Task {
            defer { isCheckingToken = false }
            do {
                _ = try await Secrets.fetchPaymentMethodAccessToken()
                tokenCheckText = "✓ Token endpoint returned a token"
            } catch {
                tokenCheckText = "✗ \(error.localizedDescription)"
            }
        }
    }

    private var configuration: PayabliPayInPaymentFlowFormConfiguration {
        PayabliPayInPaymentFlowFormConfiguration(
            allowedMethods: [.card, .ach],
            defaultMethod: .card,
            cardFieldOrder: [
                .cardholderName,
                .cardNumber,
                .cardExpiration,
                .cardCvv,
                .cardZip
            ],
            achFieldOrder: [
                .achHolder,
                .achRouting,
                .achAccount,
                .achAccountType
            ],
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
                )
            ],
            hiddenValues: PayabliPayInPaymentFlowHiddenValues(
                achHolderType: .personal,
                achSecCode: .web,
                methodDescription: "Payment Method QA"
            ),
            options: PayabliPayInPaymentFlowOptions(
                achValidation: true,
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
            labelLayout: .external,
            showsFieldLabels: true,
            hiddenFieldLabels: Set(fieldsWithHiddenLabels),
            formatting: PayabliPayInPaymentFlowFormatting(
                insertsCardNumberSpaces: true,
                masksACHAccountEntry: true
            ),
            inputSizing: PayabliPayInPaymentFlowInputSizing(
                defaultSize: PayabliPayInPaymentFlowInputSize(height: 52),
                fieldSizes: [
                    .cardExpiration: PayabliPayInPaymentFlowInputSize(height: 48),
                    .cardCvv: PayabliPayInPaymentFlowInputSize(height: 48)
                ]
            ),
            cardBrandIconPlacement: .trailing
        )
    }

    private var style: PayabliPayInPaymentFlowStyle { PayInSharedConfiguration.style }

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
}
