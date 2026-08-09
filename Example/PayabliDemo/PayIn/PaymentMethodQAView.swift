import Dispatch
import os
import PayabliSDKPayInPaymentFlow
import SwiftUI

struct PaymentMethodQAView: View {
    let paymentFlow: PayabliPayInPaymentFlow

    @StateObject private var diagnosticsStore = DiagnosticsStore.paymentMethod
    @State private var resultText = ""
    @State private var isPaymentMethodAddedViewPresented = false
    @State private var isPaymentMethodSheetPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        isPaymentMethodSheetPresented = true
                    } label: {
                        Label("Open sheet experience", systemImage: "rectangle.bottomthird.inset.filled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    #if DEBUG
                    DebugPrefillButton()
                    #endif

                    Text("Inline experience")
                        .font(.headline)

                    PayabliPayInPaymentFlowView(
                        component: paymentFlow,
                        configuration: configuration,
                        onCompleted: handlePaymentMethodAdded,
                        onError: handleError
                    )
                    .payabliPayInPaymentFlowStyle(style)

                    Text(resultText.isEmpty ? "No payment method result yet" : resultText)
                        .font(.footnote)
                        .foregroundColor(.payabliOnSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.payabliSurfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    DiagnosticsSection(store: diagnosticsStore, isEnabled: Secrets.paymentMethodDiagnosticsEnabled)
                }
                .padding(16)
            }
            .navigationTitle("Payment Method QA")
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
