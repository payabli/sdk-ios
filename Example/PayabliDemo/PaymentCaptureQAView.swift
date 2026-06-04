import os
import PayabliSDKCore
import PayabliSDKPaymentCapture
import SwiftUI

struct PaymentCaptureQAView: View {
    @EnvironmentObject private var paymentCapture: PayabliPaymentCapture
    @StateObject private var diagnosticsStore = PaymentCaptureQADiagnosticsStore.shared
    @State private var resultText = ""
    @State private var capturedResult: PayabliPaymentCaptureResult?
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

                    Text("Inline experience")
                        .font(.headline)

                    PayabliPaymentCaptureView(
                        component: paymentCapture,
                        configuration: configuration,
                        onPaymentCaptured: handlePaymentCaptured,
                        onError: handleError
                    )
                    .payabliPaymentCaptureStyle(style)

                    Text(resultText.isEmpty ? "No payment capture result yet" : resultText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if Secrets.paymentCaptureDiagnosticsEnabled {
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
            .navigationTitle("Payment Capture QA")
            .navigationDestination(isPresented: $isPaymentCaptureResultViewPresented) {
                if let capturedResult {
                    PaymentCaptureResultView(result: capturedResult)
                }
            }
        }
        .payabliPaymentCaptureSheet(
            isPresented: $isPaymentCaptureSheetPresented,
            component: paymentCapture,
            configuration: configuration,
            sheetConfiguration: PayabliPaymentCaptureSheetConfiguration(
                title: "Submit Payment",
                dismissButton: .back
            ),
            style: style,
            onPaymentCaptured: handlePaymentCaptured,
            onError: handleError
        )
    }

    private var configuration: PayabliPaymentCaptureFormConfiguration {
        PayabliPaymentCaptureFormConfiguration(
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
                PayabliPaymentCaptureFieldSection(
                    title: "Card Information",
                    titleStyle: PayabliPaymentCaptureTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .cardholderName,
                        .cardNumber,
                        .cardExpiration,
                        .cardCvv,
                        .cardZip
                    ],
                    inputVerticalSpacing: 4,
                    inputHorizontalSpacing: 8,
                    fieldVerticalSpacings: [
                        .cardNumber: 2,
                        .cardCvv: 2
                    ]
                ),
                PayabliPaymentCaptureFieldSection(
                    title: "Customer Information",
                    titleStyle: PayabliPaymentCaptureTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .firstName,
                        .lastName,
                        .billingEmail
                    ]
                ),
                PayabliPaymentCaptureFieldSection(
                    title: "Payment Information",
                    titleStyle: PayabliPaymentCaptureTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .amount,
                        .serviceFee
                    ],
                    inputVerticalSpacing: 6
                )
            ],
            achSections: [
                PayabliPaymentCaptureFieldSection(
                    title: "Bank Information",
                    titleStyle: PayabliPaymentCaptureTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .achHolder,
                        .achRouting,
                        .achAccount,
                        .achAccountType
                    ],
                    inputVerticalSpacing: 4,
                    inputHorizontalSpacing: 8,
                    fieldVerticalSpacings: [
                        .achRouting: 2,
                        .achAccount: 2
                    ]
                ),
                PayabliPaymentCaptureFieldSection(
                    title: "Customer Information",
                    titleStyle: PayabliPaymentCaptureTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .firstName,
                        .lastName,
                        .billingEmail
                    ]
                ),
                PayabliPaymentCaptureFieldSection(
                    title: "Payment Information",
                    titleStyle: PayabliPaymentCaptureTextStyle(
                        font: .headline.weight(.semibold),
                        color: .primary
                    ),
                    fields: [
                        .amount,
                        .serviceFee
                    ],
                    inputVerticalSpacing: 6
                )
            ],
            hiddenValues: PayabliPaymentCaptureHiddenValues(
                achHolderType: .personal,
                achSecCode: .web,
                methodDescription: "Payment Capture QA"
            ),
            labels: PayabliPaymentCaptureLabels(
                title: "Payment Capture",
                subtitle: "Submit a card or ACH payment.",
                submitButton: "Submit Payment",
                fieldPlaceholders: labelMatchingPlaceholders(for: fieldsWithHiddenLabels)
            ),
            labelLayout: .external,
            showsFieldLabels: true,
            hiddenFieldLabels: Set(fieldsWithHiddenLabels),
            formatting: PayabliPaymentCaptureFormatting(
                insertsCardNumberSpaces: true,
                masksACHAccountEntry: true
            ),
            inputSizing: PayabliPaymentCaptureInputSizing(
                defaultSize: PayabliPaymentCaptureInputSize(height: 52),
                fieldSizes: [
                    .cardExpiration: PayabliPaymentCaptureInputSize(height: 48),
                    .cardCvv: PayabliPaymentCaptureInputSize(height: 48)
                ]
            ),
            cardBrandIconPlacement: .trailing,
            paymentSummary: PayabliPaymentCapturePaymentSummaryConfiguration(
                labelStyle: PayabliPaymentCapturePaymentSummaryTextStyle(
                    font: .subheadline,
                    color: .secondary
                ),
                valueStyle: PayabliPaymentCapturePaymentSummaryTextStyle(
                    font: .subheadline.weight(.semibold),
                    color: .primary
                ),
                rowSpacing: 6
            )
        )
    }

    private var style: PayabliPaymentCaptureStyle {
        PayabliPaymentCaptureStyle(
            accentColor: .green,
            input: PayabliPaymentCaptureInputStyle(
                backgroundColor: Color(.systemBackground),
                borderColor: Color(.separator).opacity(0.6),
                cornerRadius: 8
            ),
            submitButton: PayabliPaymentCaptureSubmitButtonStyle(cornerRadius: 8),
            layout: PayabliPaymentCaptureLayoutStyle(
                contentSpacing: 18,
                fieldGroupSpacing: 14,
                pairedFieldSpacing: 12,
                sectionSpacing: 20,
                sectionTitleSpacing: 10
            )
        )
    }

    private var fieldsWithHiddenLabels: [PayabliPaymentCaptureField] {
        [
            .cardholderName,
            .cardNumber,
            .cardExpiration,
            .cardCvv,
            .cardZip,
            .achHolder,
            .achRouting,
            .achAccount,
            .achAccountType,
            .firstName,
            .lastName,
            .billingEmail
        ]
    }

    private func labelMatchingPlaceholders(
        for fields: [PayabliPaymentCaptureField]
    ) -> [PayabliPaymentCaptureField: String] {
        Dictionary(uniqueKeysWithValues: fields.map { field in
            (
                field,
                PayabliPaymentCaptureLabels.defaultFieldLabels[field] ?? field.rawValue
            )
        })
    }

    private func handlePaymentCaptured(_ result: PayabliPaymentCaptureResult) {
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
            subsystem: "com.payabli.demo.paymentmethodqa",
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
            subsystem: "com.payabli.demo.paymentmethodqa",
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
