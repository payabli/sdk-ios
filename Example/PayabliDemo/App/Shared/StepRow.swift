import SwiftUI

/// How a status looks. The status itself is in `Flow/StepStatus.swift`.
private extension StepStatus {
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

/// One row of the sequence. It renders a step; it never decides one.
struct StepRow<Content: View>: View {
    let index: Int
    let step: FlowStep
    @ViewBuilder var content: Content

    private var status: StepStatus {
        step.status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: status.symbol)
                    .foregroundColor(status.tint)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(index). \(step.title)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(status == .blocked || status == .notNeeded
                                ? .payabliOnSurfaceVariant
                                : .payabliOnSurface)
                        Spacer(minLength: 8)
                        Text(status.label)
                            .font(.caption)
                            .foregroundColor(status.tint)
                    }
                    Text(step.detail)
                        .font(.caption)
                        .foregroundColor(.payabliOnSurfaceVariant)
                }
            }

            if status.showsContent {
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
