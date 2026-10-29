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
            if let refusal = vendorRefusal(error, shown: detail) {
                return refusal
            }
            return fallback(detail.isEmpty ? error.localizedDescription : detail)
        }

        /// Translates a read's failure: a reader session found spent is the session's expiry, not charged where the
        /// card reader refused to read without one, and unknown where it ended during the read, because the processor
        /// may take the sale before the reader answers. Any other failure is mapped as an NFC one.
        ///
        /// - Parameter error: what the read threw, before it was translated for the host.
        /// - Returns: the typed error a host receives.
        static func mapReadError(_ error: Error) -> PayabliTTPError {
            if refusedToReadWithoutASession(error) {
                return .readerSessionExpired(capture: .notCharged)
            }
            if let platform = platformError(behind: error), readerFailureInvalidatesSession(platform) {
                return .readerSessionExpired(capture: .unknown)
            }
            return mapError(error) { .nfcFailed(reason: $0) }
        }

        /// The card reader's refusal to read without a session, raised before any card is asked for. It names
        /// itself only in text.
        static let noSessionRefusal = (
            title: "Invalid Session",
            description: "The card reader session has not been initialized."
        )

        /// Whether the card reader refused the read because it holds no session, either directly or kept behind
        /// the charge's own failure.
        ///
        /// - Parameter error: what the read threw, before it was translated for the host.
        /// - Returns: `true` where the refusal is the card reader's own missing-session check.
        static func refusedToReadWithoutASession(_ error: Error) -> Bool {
            [error, platformError(behind: error)].contains { candidate in
                guard let refusal = candidate as? FiservTTPCardReaderError else { return false }
                return refusal.title == noSessionRefusal.title
                    && refusal.localizedDescription == noSessionRefusal.description
            }
        }

        /// The refusal the vendor named, where the failure reason it kept carries the processor's own code.
        ///
        /// Only a code that decodes out names a refusal; an error whose reason is not the vendor's JSON keeps the
        /// caller's own classification.
        ///
        /// - Parameter error: what the reader stack threw, before it was translated for the host.
        /// - Parameter shown: the detail a host is shown, which the refusal carries as its reason.
        /// - Returns: the vendor's refusal, or `nil` where it named none.
        static func vendorRefusal(_ error: Error, shown: String) -> PayabliTTPError? {
            guard let readerError = error as? FiservTTPCardReaderError,
                  let body = readerError.failureReason?.data(using: .utf8),
                  let codes = try? JSONDecoder().decode(VendorFailure.self, from: body).codes,
                  !codes.isEmpty
            else { return nil }
            if codes.contains(where: deviceDeniedCodes.contains) {
                return .readerDeviceRefused(reason: shown)
            }
            return .readerUnavailable(reason: shown)
        }

        /// The vendor's codes that say it refused the handset, the refusal confirmed or not.
        private static let deviceDeniedCodes: Set<String> = ["677", "018", "670", "202", "745", "705"]

        /// The vendor's failure reason, decoded: a top-level `responseCode`, and the `code` of each entry in the
        /// `error` list its server error envelope carries.
        private struct VendorFailure: Decodable {
            let responseCode: String?
            let error: [VendorFailureEntry]?

            var codes: [String] {
                [responseCode].compactMap(\.self) + (error ?? []).compactMap(\.code)
            }
        }

        /// One entry in the `error` list of the vendor's server error envelope.
        private struct VendorFailureEntry: Decodable {
            let code: String?
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
