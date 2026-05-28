import SwiftUI

struct PaymentMethodAddedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 104, weight: .semibold))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Added a new payment method.")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
    }
}
