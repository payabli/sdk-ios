import Foundation
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
    let outcome: PayInOutcome

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
                        Text(outcome.headline)
                            .font(.subheadline)
                            .foregroundStyle(Color.payabliOnSurfaceVariant)
                    }
                }

                responseSummary

                VStack(alignment: .leading, spacing: 8) {
                    Text("Response")
                        .font(.headline)

                    Text(outcome.responseJSON)
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

            ForEach(outcome.summaryRows) { row in
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
}
