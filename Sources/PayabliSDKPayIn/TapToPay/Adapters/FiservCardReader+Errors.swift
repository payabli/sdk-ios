import Foundation
import PayabliSDKCore
#if canImport(PayabliCardReaderCore) && canImport(ProximityReader)
import PayabliCardReaderCore
import ProximityReader
#endif

// MARK: - Card reader error mapping

extension FiservCardReader {

    /// Prefix inside `.nfcFailed(reason:)` that marks a user-cancel, so hosts
    /// can distinguish it from a hard failure by substring.
    static let cancellationReasonPrefix = "cancelled:"

    #if canImport(PayabliCardReaderCore) && canImport(ProximityReader)

    /// Translates a card-reader / ProximityReader error into `PayabliTTPError`.
    /// `fallback` picks the case (setup vs. NFC) for non-cancel errors.
    static func mapError(
        _ error: Error,
        fallback: (String) -> PayabliTTPError
    ) -> PayabliTTPError {
        if let pte = error as? PayabliTTPError { return pte }

        if (error as NSError).code == NSUserCancelledError {
            return .nfcFailed(
                reason: "\(cancellationReasonPrefix) user dismissed Tap to Pay sheet"
            )
        }

        if #available(iOS 16.4, *), error is PaymentCardReaderError {
            let desc = error.localizedDescription
            if desc.lowercased().contains("version") {
                return .readerSetupFailed(reason: "OS version not supported: \(desc)")
            }
        }

        let detail = extractReaderDetail(error)
        return fallback(detail.isEmpty ? error.localizedDescription : detail)
    }

    /// `FiservTTPCardReaderError.localizedDescription` is a stored property
    /// that shadows (doesn't override) `Error.localizedDescription`, so the
    /// usual accessor returns a generic NSError message. Read the real
    /// `title` + `localizedDescription` via reflection.
    static func extractReaderDetail(_ error: Error) -> String {
        let mirror = Mirror(reflecting: error)
        let title = mirror.children.first(where: { $0.label == "title" })?.value as? String
        let desc = mirror.children.first(where: { $0.label == "localizedDescription" })?.value as? String
        if let title, let desc { return "\(title): \(desc)" }
        if let desc { return desc }
        return ""
    }

    #endif
}
