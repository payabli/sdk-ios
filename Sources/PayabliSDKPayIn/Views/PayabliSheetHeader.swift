import SwiftUI
import PayabliSDKCore

/// Shared sheet chrome used by `.payabliCardSheet(...)`, `.payabliAchSheet(...)`,
/// and the UIKit `createTokenizationViewController` / `processPaymentViewController`
/// factories. Title on the leading edge, Cancel on the trailing.
@available(iOS 15.0, macOS 12.0, *)
struct PayabliSheetHeader: View {
    let title: String
    let tint: Color
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button("Cancel", action: onCancel)
                .foregroundColor(tint)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}
