import os
import PayabliSDKCore
import PayabliSDKPayInPaymentFlow
import SwiftUI

struct PaymentCaptureQAView: View {
    let paymentFlow: PayabliPayInPaymentFlow

    @StateObject private var diagnosticsStore = DiagnosticsStore.paymentCapture
    @State private var resultText = ""
    @State private var capturedResult: PayabliPayInPaymentFlowResult?
    @State private var isPaymentCaptureSheetPresented = false
    @State private var isPaymentCaptureResultViewPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        isPaymentCaptureSheetPresented = true
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
                        onCompleted: handlePaymentCaptured,
                        onError: handleError
                    )
                    .payabliPayInPaymentFlowStyle(style)

                    Text(resultText.isEmpty ? "No payment capture result yet" : resultText)
                        .font(.footnote)
                        .foregroundColor(.payabliOnSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.payabliSurfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    DiagnosticsSection(store: diagnosticsStore, isEnabled: Secrets.paymentCaptureDiagnosticsEnabled)
                }
                .padding(16)
            }
            .navigationTitle("Payment Capture QA")
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
                methodDescription: "Payment Capture QA"
            ),
            labels: PayabliPayInPaymentFlowLabels(
                title: "Payment Capture",
                subtitle: "Submit a card or ACH payment.",
                submitButton: "Submit Payment",
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
            cardBrandIconPlacement: .trailing,
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

    private var style: PayabliPayInPaymentFlowStyle { PayInSharedConfiguration.style }

    private var fieldsWithHiddenLabels: [PayabliPayInPaymentFlowField] {
        PayInSharedConfiguration.fieldsWithHiddenLabels
    }

    private func labelMatchingPlaceholders(
        for fields: [PayabliPayInPaymentFlowField]
    ) -> [PayabliPayInPaymentFlowField: String] {
        PayInSharedConfiguration.labelMatchingPlaceholders(for: fields)
    }

    private func handlePaymentCaptured(_ result: PayabliPayInPaymentFlowResult) {
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
        let message = paymentCaptureErrorMessage(error)
        resultText = "Payment capture failed: \(message)"
        Logger(
            subsystem: "com.payabli.example.app",
            category: "PaymentCaptureDiagnostics"
        ).error("Payment capture failed: \(message, privacy: .public)")
    }

    private func paymentCaptureErrorMessage(_ error: Error) -> String {
        if let payabliError = error as? any PayabliError {
            if let detail = payabliError.detail, !detail.isEmpty, detail != payabliError.reason {
                return "\(payabliError.reason)\n\(detail)"
            }
            return payabliError.reason
        }
        return String(describing: error)
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
}

