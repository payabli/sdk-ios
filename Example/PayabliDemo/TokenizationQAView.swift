import os
import PayabliSDKTokenization
import SwiftUI

struct TokenizationQAView: View {
    @EnvironmentObject private var tokenization: PayabliTokenization
    @StateObject private var diagnosticsStore = TokenizationQADiagnosticsStore.shared
    @State private var resultText = ""
    @State private var isTokenizationSheetPresented = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        isTokenizationSheetPresented = true
                    } label: {
                        Label("Open sheet experience", systemImage: "rectangle.bottomthird.inset.filled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Inline experience")
                        .font(.headline)

                    PayabliTokenizationView(
                        component: tokenization,
                        configuration: configuration,
                        onTokenized: handleTokenized,
                        onError: handleError
                    )
                    .payabliTokenizationStyle(style)

                    Text(resultText.isEmpty ? "No tokenization result yet" : resultText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if Secrets.tokenizationDiagnosticsEnabled {
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
            .navigationTitle("Tokenization QA")
        }
        .payabliTokenizationSheet(
            isPresented: $isTokenizationSheetPresented,
            component: tokenization,
            configuration: configuration,
            sheetConfiguration: PayabliTokenizationSheetConfiguration(
                title: "Add Payment Method",
                dismissButton: .back
            ),
            style: style,
            onTokenized: handleTokenized,
            onError: handleError
        )
    }

    private var configuration: PayabliTokenizationFormConfiguration {
        PayabliTokenizationFormConfiguration(
            allowedMethods: [.card, .ach],
            defaultMethod: .card,
            cardFieldOrder: [
                .cardNumber,
                .cardExpiration,
                .cardCvv,
                .cardZip,
                .cardholderName
            ],
            achFieldOrder: [
                .achHolder,
                .achRouting,
                .achAccount,
                .achAccountType
            ],
            hiddenValues: PayabliTokenizationHiddenValues(
                achHolderType: .personal,
                achSecCode: .web,
                methodDescription: "Tokenization QA"
            ),
            options: PayabliTokenizationOptions(
                achValidation: true,
                createAnonymous: false,
                forceCustomerCreation: true,
                temporary: false,
                source: "ios-tokenization-qa"
            ),
            labels: PayabliTokenizationLabels(
                title: "Save Payment Method",
                subtitle: "Create a card or ACH token.",
                submitButton: "Tokenize"
            ),
            labelLayout: .external,
            formatting: PayabliTokenizationFormatting(
                insertsCardNumberSpaces: true,
                masksACHAccountEntry: true
            ),
            inputSizing: PayabliTokenizationInputSizing(
                defaultSize: PayabliTokenizationInputSize(height: 52),
                fieldSizes: [
                    .cardExpiration: PayabliTokenizationInputSize(height: 48),
                    .cardCvv: PayabliTokenizationInputSize(height: 48)
                ]
            ),
            cardBrandIconPlacement: .trailing
        )
    }

    private var style: PayabliTokenizationStyle {
        PayabliTokenizationStyle(
            accentColor: .green,
            input: PayabliTokenizationInputStyle(
                backgroundColor: Color(.systemBackground),
                borderColor: Color(.separator).opacity(0.6),
                cornerRadius: 8
            ),
            submitButton: PayabliTokenizationSubmitButtonStyle(cornerRadius: 8),
            layout: PayabliTokenizationLayoutStyle(contentSpacing: 18, fieldGroupSpacing: 12)
        )
    }

    private func handleTokenized(_ method: PayabliTokenizedMethod) {
        resultText = [
            "Stored method: \(method.storedMethodId ?? "-")",
            "Response: \(method.responseText)",
            "Result: \(method.resultText ?? "-")"
        ].joined(separator: "\n")
        Logger(
            subsystem: "com.payabli.demo.tokenizationqa",
            category: "TokenizationDiagnostics"
        ).info("Tokenization succeeded: \(method.responseText, privacy: .public)")
    }

    private func handleError(_ error: Error) {
        resultText = "Tokenization failed: \(error.localizedDescription)"
        Logger(
            subsystem: "com.payabli.demo.tokenizationqa",
            category: "TokenizationDiagnostics"
        ).error("Tokenization failed: \(error.localizedDescription, privacy: .public)")
    }
}
