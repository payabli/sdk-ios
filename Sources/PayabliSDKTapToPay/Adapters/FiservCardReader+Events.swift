import Foundation
#if canImport(PayabliCardReaderCore) && canImport(ProximityReader)
    internal import PayabliCardReaderCore
    import ProximityReader
#endif

// MARK: - Card reader event mapping

extension FiservCardReader {
    #if canImport(PayabliCardReaderCore) && canImport(ProximityReader)

        /// Translates a platform reader event into the SDK's own vocabulary.
        ///
        /// `nil` means the event has no counterpart and is dropped. A read
        /// starting, completing and failing reaches a host through the charge
        /// itself, so those four cases are in that set.
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
        static func clampToPercentage(_ value: Int) -> Int {
            min(max(value, 0), 100)
        }

    #endif
}
