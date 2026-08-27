import PayabliSDKPayInPaymentFlow
import SwiftUI

/// Where the SDK's payment form mounts.
///
/// Both payment screens use it twice each, inline and inside a sheet, and neither
/// knows what it renders. The app owns the call site, which form to show, the
/// outcome and failure models, the sheet chrome and both result screens.
///
/// **The SDK submits.** The payer's tap runs the form's operation through the
/// flow, and the answer arrives on one of the two callbacks translated into this
/// app's own types, so no screen below holds an SDK outcome.
struct PaymentFormHost: View {
    let flow: PayInFlowHandle
    let form: PayInFormSetup
    let onCompleted: (PayInOutcome) -> Void
    let onFailed: (PayInFailure) -> Void

    var body: some View {
        PayabliPayInPaymentFlowView(
            component: flow.flow,
            configuration: form.configuration,
            onCompleted: { onCompleted(PayInOutcome($0)) },
            onError: { onFailed(PayInFailure($0, operation: form.operation)) }
        )
        .payabliPayInPaymentFlowStyle(form.style)
    }
}

extension View {
    /// The same form in a sheet, with this app's title on it.
    func paymentFormSheet(
        isPresented: Binding<Bool>,
        flow: PayInFlowHandle,
        form: PayInFormSetup,
        title: String,
        onCompleted: @escaping (PayInOutcome) -> Void,
        onFailed: @escaping (PayInFailure) -> Void
    ) -> some View {
        payabliPayInPaymentFlowSheet(
            isPresented: isPresented,
            component: flow.flow,
            configuration: form.configuration,
            sheetConfiguration: PayabliPayInPaymentFlowSheetConfiguration(
                title: title,
                dismissButton: .back
            ),
            style: form.style,
            onCompleted: { onCompleted(PayInOutcome($0)) },
            onError: { onFailed(PayInFailure($0, operation: form.operation)) }
        )
    }
}
