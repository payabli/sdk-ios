import Foundation
#if canImport(PayabliCardReaderCore) && canImport(ProximityReader)
    internal import PayabliCardReaderCore
    import ProximityReader
#endif

// MARK: - Card reader event mapping

@available(iOS 16.7, *)
extension FiservCardReader {
    #if canImport(PayabliCardReaderCore) && canImport(ProximityReader)

        /// Translates a platform reader event into the SDK's own vocabulary.
        ///
        /// A read's own start, completion and failure reach a host through the charge itself, so
        /// those events map to `nil` here.
        ///
        /// - Parameter event: the platform event the reader reported.
        /// - Returns: the SDK's counterpart, or `nil` where the SDK has no word for the event, which drops it.
        static func mapReaderEvent(_ event: PaymentCardReader.Event) -> TapToPayReaderEvent? {
            switch event {
            case let .updateProgress(percent):
                return .configurationProgress(percent: clampToPercentage(percent))
            case .notReady:
                return .notReady
            case .cardDetected:
                return .cardDetected
            case .removeCard:
                return .cardRemovalRequested
            case .readRetry:
                return .cardReadRetryRequested
            case .pinEntryRequested:
                return .pinEntryRequested
            case .pinEntryCompleted:
                return .pinEntryCompleted
            case .userInterfaceDismissed:
                return .promptDismissed
            case .readyForTap, .readCompleted, .readCancelled, .readNotCompleted:
                return nil
            @unknown default:
                return nil
            }
        }

        /// The platform carries the completion percentage as a bare `Int` and
        /// documents it only as a percentage, so the bound is asserted here
        /// rather than assumed of the value.
        ///
        /// - Parameter value: the completion percentage as the platform reported it, which it does not bound.
        /// - Returns: the percentage, held inside 0 through 100.
        static func clampToPercentage(_ value: Int) -> Int {
            min(max(value, 0), 100)
        }

    #endif
}
