import SwiftUI

/// Renders a `DiagnosticsStore`'s rolling log, for any tab that has one.
struct DiagnosticsSection: View {
    @ObservedObject var store: DiagnosticsStore

    /// When false the section renders nothing, matching the old per-tab
    /// `if Secrets.…DiagnosticsEnabled` wrapper.
    let isEnabled: Bool

    var body: some View {
        if isEnabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("Diagnostics")
                    .font(.headline)

                if store.messages.isEmpty {
                    Text("No diagnostics yet")
                        .font(.footnote)
                        .foregroundColor(.payabliOnSurfaceVariant)
                } else {
                    ForEach(Array(store.messages.enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .font(.caption.monospaced())
                            .foregroundColor(.payabliOnSurfaceVariant)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.payabliSurfaceContainerHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}
