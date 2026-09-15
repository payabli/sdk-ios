import Foundation

// MARK: - Reader events

extension PayabliTTP {
    /// Announces progress only for the configuration that installed this
    /// handler. Every other reader event is announced whenever it arrives.
    func handleReaderEvent(_ event: TapToPayReaderEvent, from configuration: Int) {
        if case .configurationProgress = event, configuration != activeConfiguration {
            return
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
