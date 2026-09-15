import Foundation

// MARK: - Reader events

extension PayabliTTP {
    /// Publishes progress only for the configuration that installed this
    /// handler, and records it before announcing it.
    func handleReaderEvent(_ event: TapToPayReaderEvent, from configuration: Int) {
        if case let .configurationProgress(percent) = event {
            guard configuration == activeConfiguration else { return }
            readerConfigurationProgress = percent
        }
        multicaster.emit(published(event))
    }

    private func published(_ event: TapToPayReaderEvent) -> PayabliTTPEvent {
        switch event {
        case let .configurationProgress(percent):
            return .readerConfigurationProgressChanged(percent: percent)
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
