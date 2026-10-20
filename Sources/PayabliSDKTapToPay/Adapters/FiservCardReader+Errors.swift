import Foundation
import PayabliSDKCore
#if canImport(PayabliCardReaderCore)
    internal import PayabliCardReaderCore
    import ProximityReader
#endif

// MARK: - Card reader error mapping

@available(iOS 16.7, *)
extension FiservCardReader {
    #if canImport(PayabliCardReaderCore)

        /// Translates a card-reader / ProximityReader error into `PayabliTTPError`.
        /// `fallback` picks the case (setup vs. NFC), including for a user cancel: dismissing
        /// the terms sheet is a setup failure, dismissing the tap sheet is an NFC one.
        ///
        /// - Parameter error: what the reader stack threw, before it was translated for the host.
        /// - Parameter fallback: builds the case from the detail text a host is shown.
        /// - Returns: the typed error a host receives.
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
                    "\(PayabliTTPError.cancellationReasonPrefix) user dismissed Tap to Pay sheet"
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

        /// The platform error behind a card-reader component error, where it kept one.
        ///
        /// The component only ever throws its own type, so this is the only way to tell one refusal from another without matching prose.
        ///
        /// - Parameter error: what the reader stack threw, which may be the component's own wrapper type.
        /// - Returns: the platform error behind the wrapper, or the error as thrown where there is none.
        static func platformError(behind error: Error) -> Error? {
            (error as? FiservTTPCardReaderError)?.underlying ?? error
        }

        /// Whether the payer or the platform ended the read.
        ///
        /// - Parameter error: the error the read ended with, nil where none was thrown.
        /// - Returns: whether the read was cancelled, which the public edge reports as `USER_CANCELLED`.
        static func isCancellation(_ error: Error?) -> Bool {
            if let readError = error as? PaymentCardReaderSession.ReadError, case .readCancelled = readError {
                return true
            }
            return false
        }

        /// `title` and `localizedDescription` together, which is what a host is
        /// shown when nothing more specific was recognised.
        ///
        /// - Parameter error: what the reader stack threw, before it was translated for the host.
        /// - Returns: the two joined, or an empty string where the error is not the component's own.
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
