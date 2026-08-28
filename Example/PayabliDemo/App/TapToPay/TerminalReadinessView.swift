import SwiftUI

/// Terminal readiness, reported as a verdict plus only the reasons it is not
/// ready.
///
/// Replaces the old always-on "Pre-flight" list. A passing check is not news:
/// when everything passes this collapses to a single green line, and what
/// remains on screen is exactly the set of things standing in the way.
///
/// The checks behind it stay mutually independent — see `TapToPayPreflight` —
/// which is the property that makes a single rolled-up verdict trustworthy.
struct TerminalReadinessView: View {
    let configuredAppId: String

    /// Computed on appearance, not per body evaluation: each run does a `uname`,
    /// hits `DCAppAttestService`, and reads the provisioning profile.
    ///
    /// `nil` before that first run, never an empty array. The rollup fails only
    /// on a failed check, so an empty set would read as ready.
    @State private var checks: [TapToPayPreflight.Check]?

    private var readiness: TapToPayPreflight.Readiness? {
        checks.map(TapToPayPreflight.readiness(from:))
    }

    /// Everything that is not a clean pass. Empty means nothing to report.
    private var problems: [TapToPayPreflight.Check] {
        (checks ?? []).filter { $0.status != .pass }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: headerSymbol)
                    .foregroundColor(headerColor)
                Text(headerTitle)
                    .font(.headline)
                    .foregroundColor(headerColor)
                Spacer()
                Button("Re-check") { refresh() }
                    .font(.footnote)
            }

            if readiness == nil {
                Text("Reading the host, App Attest, the reader and the provisioning profile.")
                    .font(.caption)
                    .foregroundColor(.payabliOnSurfaceVariant)
            } else if problems.isEmpty {
                Text("Every check passed.")
                    .font(.caption)
                    .foregroundColor(.payabliOnSurfaceVariant)
            } else {
                ForEach(problems) { check in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: symbol(for: check.status))
                            .foregroundColor(color(for: check.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                                .font(.footnote.weight(.semibold))
                            Text(check.detail)
                                .font(.caption)
                                .foregroundColor(.payabliOnSurfaceVariant)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.payabliSurfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private var headerTitle: String {
        readiness?.title ?? "Checking the terminal"
    }

    private var headerSymbol: String {
        switch readiness {
        case .none: return "hourglass"
        case .ready: return "checkmark.seal.fill"
        case .notAvailable: return "xmark.octagon.fill"
        }
    }

    private var headerColor: Color {
        switch readiness {
        case .none: return .payabliOnSurfaceVariant
        case .ready: return .payabliSuccess
        case .notAvailable: return .payabliError
        }
    }

    private func refresh() {
        checks = TapToPayPreflight.checks(configuredAppId: configuredAppId)
    }

    private func symbol(for status: TapToPayPreflight.Check.Status) -> String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func color(for status: TapToPayPreflight.Check.Status) -> Color {
        switch status {
        case .pass: return .payabliSuccess
        case .warn: return .payabliWarning
        case .fail: return .payabliError
        case .unknown: return .secondary
        }
    }
}
