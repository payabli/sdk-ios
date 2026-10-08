import Foundation

// MARK: - Reader events

extension PayabliTTP {
    /// Records configuration progress, and a prompt the reader raises during a
    /// charge, on the state each belongs to.
    ///
    /// Progress reaches the state only for the configuration that installed this
    /// handler, so a percentage raised by one that has ended is dropped. A prompt
    /// reaches it only from the reader now prepared, and only while a charge holds
    /// the session.
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
