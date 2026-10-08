import Foundation

// MARK: - Reader events

extension PayabliTTP {
    /// Progress counts only from the configuration still running, and a prompt only
    /// from the reader now prepared while a charge holds the session.
    func handleReaderEvent(_ event: TapToPayReaderEvent, from configuration: Int) {
        if case let .configurationProgress(percent) = event {
            guard configuration == activeConfiguration else { return }
            sessionManager.recordConfigurationProgress(percent)
            syncPublished()
            return
        }
        guard configuration == preparedReader,
              let charge = sessionManager.runningCharge,
              let activity = Self.chargeActivity(for: event)
        else { return }
        recordChargeActivity(activity, for: charge)
    }

    /// The activity a reader prompt reports, or `nil` for an event that reaches a
    /// host some other way.
    private static func chargeActivity(for event: TapToPayReaderEvent) -> TapToPayChargeActivity? {
        switch event {
        case .configurationProgress, .notReady:
            return nil
        case .cardDetected:
            return .cardDetected
        case .cardRemovalRequested:
            return .cardRemovalRequested
        case .cardReadRetryRequested:
            return .cardReadRetryRequested
        case .pinEntryRequested:
            return .pinEntryRequested
        case .pinEntryCompleted:
            return .pinEntryCompleted
        case .promptDismissed:
            return .readerPromptDismissed
        }
    }
}
