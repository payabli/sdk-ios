import SwiftUI

/// A read-only label/value row with an optional problem note.
///
/// Shared by the Tap to Pay and Configuration tabs so the two cannot drift.
/// Read-only by construction — `Text`, never `TextField` — because the values it
/// shows were captured by the SDK facades at launch, so an editable field would
/// promise something the app cannot honour.
struct QADetailRow: View {
    let label: String
    let value: String
    var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.payabliOnSurfaceVariant)
                Spacer(minLength: 12)
                Text(value.isEmpty ? "—" : value)
                    .font(.subheadline.monospaced())
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.payabliWarning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.payabliSurfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
