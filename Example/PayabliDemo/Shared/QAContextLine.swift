import PayabliSDKCore
import SwiftUI

/// "What am I pointed at", in one line.
///
/// The full set of values lives on the Config tab. Repeating them on every
/// payment tab is what turned those screens into walls of read-only rows.
struct QAContextLine: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
            Text(DemoConfiguration.entryPoint)
                .fontWeight(.semibold)
            Text("·")
            Text(DemoConfiguration.environment.baseURL.host ?? "—")
            Spacer()
            Text("details in Config")
        }
        .font(.caption)
        .foregroundColor(.payabliOnSurfaceVariant)
    }
}
