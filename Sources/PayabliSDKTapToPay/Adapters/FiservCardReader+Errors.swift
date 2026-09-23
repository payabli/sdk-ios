import Foundation
import PayabliSDKCore
#if canImport(PayabliCardReaderCore)
    import PayabliCardReaderCore
    import ProximityReader
#endif

// MARK: - Card reader error mapping

extension FiservCardReader {
    /// Prefix inside `.nfcFailed(reason:)` that marks a user-cancel, so hosts
    /// can distinguish it from a hard failure by substring.
    static let cancellationReasonPrefix = "cancelled:"

    #if canImport(PayabliCardReaderCore)

        /// Translates a card-reader / ProximityReader error into `PayabliTTPError`.
        /// `fallback` picks the case (setup vs. NFC), including for a user cancel: dismissing
        /// the terms sheet is a setup failure, dismissing the tap sheet is an NFC one.
        static func mapError(
            _ error: Error,
            fallback: (String) -> PayabliTTPError
        ) -> PayabliTTPError {
            if let pte = error as? PayabliTTPError {
                return pte
            }

            let platform = platformError(behind: error)

            if isCancellation(platform) || (error as NSError).code == NSUserCancelledError {
                return fallback(
                    "\(cancellationReasonPrefix) user dismissed Tap to Pay sheet"
                )
            }

            if let readerError = platform as? PaymentCardReaderError,
               readerError.isUnsupportedOSVersion
            {
                return .readerOSVersionNotSupported()
            }

            let detail = readerDetail(error)
            return fallback(detail.isEmpty ? error.localizedDescription : detail)
        }

        /// The platform error the card-reader component was built from, where it
        /// kept one.
        ///
        /// That component's throwing methods only ever throw their own type, so
        /// this is the only way to tell one refusal from another without
        /// matching prose.
        static func platformError(behind error: Error) -> Error? {
            (error as? FiservTTPCardReaderError)?.underlying ?? error
        }

        /// Whether the payer or the platform ended the read.
        static func isCancellation(_ error: Error?) -> Bool {
            if let readError = error as? PaymentCardReaderSession.ReadError, case .readCancelled = readError {
                return true
            }
            return false
        }

        /// `title` and `localizedDescription` together, which is what a host is
        /// shown when nothing more specific was recognised.
        static func readerDetail(_ error: Error) -> String {
            guard let readerError = error as? FiservTTPCardReaderError else {
                return ""
            }
            return "\(readerError.title): \(readerError.localizedDescription)"
        }

    #endif
}

#if canImport(PayabliCardReaderCore)

    private extension PaymentCardReaderError {
        /// The reader will never work on this OS build, whatever the caller does.
        ///
        /// Matched on the case rather than on the description, which is
        /// localized and which the platform does not promise the wording of.
        var isUnsupportedOSVersion: Bool {
            if case .osVersionNotSupported = self {
                return true
            }
            return false
        }
    }

#endif
