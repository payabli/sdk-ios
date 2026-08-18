import PayabliSDKCore
import SwiftUI

/// Which paypoint and which host this build runs against, in one line.
///
/// The full set of values lives on the Config tab. Repeating them on every
/// payment tab is what turned those screens into walls of read-only rows.
struct QAContextLine: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
            Text(DemoConfiguration.entryPoint.isEmpty ? "—" : DemoConfiguration.entryPoint)
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
