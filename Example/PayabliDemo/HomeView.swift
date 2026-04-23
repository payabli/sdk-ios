import SwiftUI
import PayabliSDKCore
import PayabliSDKPayIn

/// Demo app landing screen exercising every public PayIn API.
/// Maps directly to the manual QA checklist (PRD §12.3).
struct HomeView: View {
    @State private var lastResult: String = ""
    @State private var presentingCard = false
    @State private var presentingACH = false
    @State private var presentingCardPayment = false
    @State private var presentingACHPayment = false

    var body: some View {
        NavigationView {
            List {
                Section("Tokenization (FR-1, FR-2)") {
                    Button("Tokenize card") { presentingCard = true }
                    Button("Tokenize ACH") { presentingACH = true }
                }
                Section("Payment processing (FR-12)") {
                    Button("Charge card $9.99") { presentingCardPayment = true }
                    Button("Charge ACH $19.99") { presentingACHPayment = true }
                    Button("Charge stored method", action: chargeStoredMethod)
                }
                Section("Last result") {
                    Text(lastResult.isEmpty ? "—" : lastResult)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("PayabliSDK Demo")
            .sheet(isPresented: $presentingCard) {
                TokenizationSheet(type: .card) { result in
                    lastResult = result
                    presentingCard = false
                }
            }
            .sheet(isPresented: $presentingACH) {
                TokenizationSheet(type: .ach) { result in
                    lastResult = result
                    presentingACH = false
                }
            }
            .sheet(isPresented: $presentingCardPayment) {
                PaymentSheet(
                    type: .card,
                    request: PayabliPaymentRequest(
                        totalAmount: 9.99,
                        orderDescription: "Demo card charge",
                        saveIfSuccess: true
                    )
                ) { result in
                    lastResult = result
                    presentingCardPayment = false
                }
            }
            .sheet(isPresented: $presentingACHPayment) {
                PaymentSheet(
                    type: .ach,
                    request: PayabliPaymentRequest(
                        totalAmount: 19.99,
                        orderDescription: "Demo ACH charge"
                    )
                ) { result in
                    lastResult = result
                    presentingACHPayment = false
                }
            }
        }
    }

    // MARK: - Stored-method

    private func chargeStoredMethod() {
        Task { @MainActor in
            let request = PayabliPaymentRequest(
                totalAmount: 5.00,
                storedMethodId: Secrets.storedMethodId,
                storedMethodUsageType: .unscheduled
            )
            await PayabliPayIn.shared.chargeStoredMethod(
                methodType: .card,
                paymentRequest: request
            ) { result, error in
                if let result {
                    lastResult = "Charged stored method → \(result.paymentTransId)"
                } else if let error {
                    lastResult = "Stored charge failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Sheet wrappers

private struct TokenizationSheet: UIViewControllerRepresentable {
    let type: PayabliPaymentType
    let completion: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        PayabliPayIn.shared.createTokenizationViewController(type: type) { token, error in
            if let token {
                completion("Token: \(token)")
            } else if let error {
                completion("Error: \(error.localizedDescription)")
            }
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private struct PaymentSheet: UIViewControllerRepresentable {
    let type: PayabliPaymentType
    let request: PayabliPaymentRequest
    let completion: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        PayabliPayIn.shared.createPaymentViewController(
            type: type,
            paymentRequest: request
        ) { result, error in
            if let result {
                completion("Approved: \(result.paymentTransId) (\(result.responseCode))")
            } else if let error {
                completion("Declined/Failed: \(error.localizedDescription)")
            }
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
