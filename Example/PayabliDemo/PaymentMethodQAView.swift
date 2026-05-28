import Dispatch
import os
import PayabliSDKPaymentMethod
import SwiftUI

struct PaymentMethodQAView: View {
    @EnvironmentObject private var paymentMethod: PayabliPaymentMethod
    @StateObject private var diagnosticsStore = PaymentMethodQADiagnosticsStore.shared
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

                    Text("Inline experience")
                        .font(.headline)

                    PayabliPaymentMethodView(
                        component: paymentMethod,
                        configuration: configuration,
                        onPaymentMethodAdded: handlePaymentMethodAdded,
                        onError: handleError
                    )
                    .payabliPaymentMethodStyle(style)

                    Text(resultText.isEmpty ? "No payment method result yet" : resultText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if Secrets.paymentMethodDiagnosticsEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Diagnostics")
                                .font(.headline)

                            if diagnosticsStore.messages.isEmpty {
                                Text("No diagnostics yet")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(Array(diagnosticsStore.messages.enumerated()), id: \.offset) { _, message in
                                    Text(message)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(Color(.tertiarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Payment Method QA")
            .navigationDestination(isPresented: $isPaymentMethodAddedViewPresented) {
                PaymentMethodAddedView()
            }
        }
        .payabliPaymentMethodSheet(
            isPresented: $isPaymentMethodSheetPresented,
            component: paymentMethod,
            configuration: configuration,
            sheetConfiguration: PayabliPaymentMethodSheetConfiguration(
                title: "Add Payment Method",
                dismissButton: .back
            ),
            style: style,
            onPaymentMethodAdded: handlePaymentMethodAdded,
            onError: handleError
        )
    }

    private var configuration: PayabliPaymentMethodFormConfiguration {
        PayabliPaymentMethodFormConfiguration(
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
            hiddenValues: PayabliPaymentMethodHiddenValues(
                achHolderType: .personal,
                achSecCode: .web,
                methodDescription: "Payment Method QA"
            ),
            options: PayabliPaymentMethodOptions(
                achValidation: true,
                createAnonymous: false,
                forceCustomerCreation: true,
                temporary: false,
                source: "ios-payment-method-qa"
            ),
            labels: PayabliPaymentMethodLabels(
                title: "Save Payment Method",
                subtitle: "Create a card or ACH token."
            ),
            labelLayout: .external,
            formatting: PayabliPaymentMethodFormatting(
                insertsCardNumberSpaces: true,
                masksACHAccountEntry: true
            ),
            inputSizing: PayabliPaymentMethodInputSizing(
                defaultSize: PayabliPaymentMethodInputSize(height: 52),
                fieldSizes: [
                    .cardExpiration: PayabliPaymentMethodInputSize(height: 48),
                    .cardCvv: PayabliPaymentMethodInputSize(height: 48)
                ]
            ),
            cardBrandIconPlacement: .trailing
        )
    }

    private var style: PayabliPaymentMethodStyle {
        PayabliPaymentMethodStyle(
            accentColor: .green,
            input: PayabliPaymentMethodInputStyle(
                backgroundColor: Color(.systemBackground),
                borderColor: Color(.separator).opacity(0.6),
                cornerRadius: 8
            ),
            submitButton: PayabliPaymentMethodSubmitButtonStyle(cornerRadius: 8),
            layout: PayabliPaymentMethodLayoutStyle(contentSpacing: 18, fieldGroupSpacing: 12)
        )
    }

    private func handlePaymentMethodAdded(_ method: PayabliStoredPaymentMethod) {
        resultText = [
            "Stored method: \(method.storedMethodId ?? "-")",
            "Response: \(method.responseText)",
            "Result: \(method.resultText ?? "-")"
        ].joined(separator: "\n")
        Logger(
            subsystem: "com.payabli.demo.paymentmethodqa",
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
            subsystem: "com.payabli.demo.paymentmethodqa",
            category: "PaymentMethodDiagnostics"
        ).error("Payment method failed: \(error.localizedDescription, privacy: .public)")
    }
}
