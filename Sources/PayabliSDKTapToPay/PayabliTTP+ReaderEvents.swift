import Foundation

// MARK: - Reader events

extension PayabliTTP {
    /// Records progress on the state it belongs to, and announces every other
    /// reader event.
    ///
    /// Progress reaches the state only for the configuration that installed this
    /// handler, so a percentage raised by one that has ended is dropped.
    func handleReaderEvent(_ event: TapToPayReaderEvent, from configuration: Int) {
        if case let .configurationProgress(percent) = event {
            guard configuration == activeConfiguration else { return }
            sessionManager.recordConfigurationProgress(percent)
            syncPublished()
            return
        }
        guard let announcement = published(event) else { return }
        multicaster.emit(announcement)
    }

    /// The host-facing counterpart, or `nil` for a reader event that reaches a
    /// host some other way.
    private func published(_ event: TapToPayReaderEvent) -> PayabliTTPEvent? {
        switch event {
        case .configurationProgress:
            return nil
        case .notReady:
            return .readerNotReady
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
