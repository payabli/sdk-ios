import SwiftUI

/// One step of a QA flow, with its own status and action.
///
/// Shared by every payment tab so they read the same way. Each screen used to be
/// a flat set of controls that were all always tappable, which said nothing
/// about what to do first. These steps mirror the order the SDK enforces, so the
/// next thing to do is the only thing offered.
enum QAStepStatus {
    /// Finished, and nothing more to do here.
    case done
    /// The next thing to do.
    case current
    /// Underway inside the SDK; the app is waiting, not the person.
    case inProgress
    /// Cannot run until an earlier step finishes.
    case blocked
    /// Genuinely does not apply to this device or session.
    case notNeeded
    /// Attempted and failed.
    case failed

    var label: String {
        switch self {
        case .done: return "done"
        case .current: return "do this next"
        case .inProgress: return "working…"
        case .blocked: return "waiting"
        case .notNeeded: return "not needed"
        case .failed: return "failed"
        }
    }

    var symbol: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .current: return "arrowtriangle.right.circle.fill"
        case .inProgress: return "clock.fill"
        case .blocked: return "circle.dotted"
        case .notNeeded: return "minus.circle"
        case .failed: return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .done: return .payabliSuccess
        case .current: return .payabliPrimary
        case .inProgress: return .payabliPrimary
        case .blocked: return .payabliNeutral
        case .notNeeded: return .payabliNeutral
        case .failed: return .payabliError
        }
    }
}

/// One row of the sequence.
struct QAStepRow<Content: View>: View {
    let index: Int
    let title: String
    let detail: String
    let status: QAStepStatus
    @ViewBuilder var content: Content

    /// Only the step being acted on shows its controls. Anything else would put
    /// the reader back in front of buttons that do not apply yet.
    private var showsContent: Bool {
        switch status {
        case .current, .failed: return true
        case .done, .inProgress, .blocked, .notNeeded: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: status.symbol)
                    .foregroundColor(status.tint)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(index). \(title)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(status == .blocked || status == .notNeeded
                                ? .payabliOnSurfaceVariant
                                : .payabliOnSurface)
                        Spacer(minLength: 8)
                        Text(status.label)
                            .font(.caption)
                            .foregroundColor(status.tint)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.payabliOnSurfaceVariant)
                }
            }

            if showsContent {
                content
                    .padding(.leading, 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(status == .current
            ? Color.payabliSurfaceContainerHigh
            : Color.payabliSurfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
