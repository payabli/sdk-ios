import Foundation

// MARK: - Reader events

extension PayabliTTP {
    /// Records configuration progress on the state it belongs to.
    ///
    /// Progress reaches the state only for the configuration that installed this
    /// handler, so a percentage raised by one that has ended is dropped.
    func handleReaderEvent(_ event: TapToPayReaderEvent, from configuration: Int) {
        guard case let .configurationProgress(percent) = event, configuration == activeConfiguration else { return }
        sessionManager.recordConfigurationProgress(percent)
        syncPublished()
    }
}
