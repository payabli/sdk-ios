import SwiftUI
import PayabliSDKCore

/// Root SwiftUI view that hosts the appropriate payment form for a given
/// `PayabliPaymentType`.
///
/// Presented as a modal sheet by the host (via `UIHostingController` +
/// `.formSheet` / `.pageSheet`) per PRD FR-3.1, FR-3.2.
@available(iOS 15.0, macOS 12.0, *)
public struct PaymentFormView: View {
    let type: PayabliPaymentType
    let theme: PayabliTheme
    let submitTitle: String
    let cardViewModel: CardFormViewModel
    let achViewModel: ACHFormViewModel
    let onSubmitCard: () -> Void
    let onSubmitACH: () -> Void
    let onCancel: () -> Void

    public init(
        type: PayabliPaymentType,
        theme: PayabliTheme,
        submitTitle: String,
        cardViewModel: CardFormViewModel,
        achViewModel: ACHFormViewModel,
        onSubmitCard: @escaping () -> Void,
        onSubmitACH: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.type = type
        self.theme = theme
        self.submitTitle = submitTitle
        self.cardViewModel = cardViewModel
        self.achViewModel = achViewModel
        self.onSubmitCard = onSubmitCard
        self.onSubmitACH = onSubmitACH
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Sheet grabber + title
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .foregroundColor(theme.primaryColor)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 8)

            Divider()

            switch type {
            case .card:
                CardFormView(
                    viewModel: cardViewModel,
                    theme: theme,
                    submitTitle: submitTitle,
                    onSubmit: onSubmitCard
                )
            case .ach:
                ACHFormView(
                    viewModel: achViewModel,
                    theme: theme,
                    submitTitle: submitTitle,
                    onSubmit: onSubmitACH
                )
            case .applePay:
                placeholder("Apple Pay — coming in Phase 4")
            case .tapToPay:
                placeholder("Tap to Pay — coming in Phase 5")
            }
        }
    }

    private var title: String {
        switch type {
        case .card: return "Card details"
        case .ach: return "Bank account"
        case .applePay: return "Apple Pay"
        case .tapToPay: return "Tap to Pay"
        }
    }

    @ViewBuilder
    private func placeholder(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message).foregroundColor(.secondary)
            Spacer()
        }
    }
}
