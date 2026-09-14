import Foundation

// MARK: - Reader events

extension PayabliTTP {
    /// Takes what the reader is doing and records it.
    ///
    /// The reader reports for the life of a session, so this is called long
    /// after `prepareReader` returned and on every tap.
    func handleReaderEvent(_ event: TapToPayReaderEvent) {
        if case let .configurationProgress(percent) = event {
            readerConfigurationPercent = percent
        }
    }
}
