import Foundation

// MARK: - Reader events

extension PayabliTTP {
    /// Records progress before announcing it, so a subscriber reading
    /// `readerConfigurationProgress` on being told it moved sees the new value.
    func handleReaderEvent(_ event: TapToPayReaderEvent) {
        if case let .configurationProgress(percent) = event {
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
