import Foundation
import PayabliSDKPayInPaymentFlow
import SwiftUI

struct PaymentMethodAddedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 104, weight: .semibold))
                .foregroundStyle(Color.payabliSuccess)
                .accessibilityHidden(true)

            Text("Added a new payment method.")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.payabliOnSurface)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color.payabliBackground)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PaymentCaptureResultView: View {
    let result: PayabliPayInPaymentFlowResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Color.payabliSuccess)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Payment submitted")
                            .font(.title2.weight(.semibold))
                        Text(result.reason ?? result.explanation ?? result.code)
                            .font(.subheadline)
                            .foregroundStyle(Color.payabliOnSurfaceVariant)
                    }
                }

                responseSummary

                VStack(alignment: .leading, spacing: 8) {
                    Text("Response")
                        .font(.headline)

                    Text(responseJSON)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.payabliOnSurfaceVariant)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.payabliSurfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
        }
        .navigationTitle("Payment Response")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.payabliBackground)
    }

    private var responseSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.headline)

            ForEach(summaryRows, id: \.label) { row in
                HStack(alignment: .top) {
                    Text(row.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.payabliOnSurfaceVariant)
                    Spacer(minLength: 16)
                    Text(row.value)
                        .font(.subheadline)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(12)
        .background(Color.payabliSurfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var summaryRows: [(label: String, value: String)] {
        let transaction = result.transaction
        return [
            ("Code", result.code),
            ("Reason", result.reason ?? "-"),
            ("Explanation", result.explanation ?? "-"),
            ("Action", result.action ?? "-"),
            ("Payment trans ID", transaction?.paymentTransId ?? "-"),
            ("Gateway trans ID", transaction?.gatewayTransId ?? "-"),
            ("Order ID", transaction?.orderId ?? "-"),
            ("Method", transaction?.method ?? "-"),
            ("Operation", transaction?.operation ?? "-"),
            ("Status", transaction?.transStatus.map(String.init) ?? "-"),
            ("Total amount", formattedAmount(transaction?.totalAmount)),
            ("Fee amount", formattedAmount(transaction?.feeAmount)),
            ("Source", transaction?.source ?? "-")
        ]
    }

    private var responseJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard
            let data = try? encoder.encode(result.apiResponse),
            let text = String(data: data, encoding: .utf8)
        else {
            return "Unable to render response JSON."
        }
        return text
    }

    private func formattedAmount(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "$ %.2f", value)
    }
}
