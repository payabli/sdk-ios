import Foundation
#if canImport(ProximityReader)
    import ProximityReader
#endif

/// Whether the reader session is gone, or only this read failed. A dead session
/// needs a fresh config and a reader re-prepare; a failed read needs neither.
///
/// The set is Apple's: `PaymentCardReaderSession.ReadError` draws this line.
///
/// Two tiers, because the type does not always survive. The card-reader
/// component rebuilds the error as a title plus a description, so on a device
/// only the case name arrives, in text.
func readerFailureInvalidatesSession(_ error: Error) -> Bool {
    #if canImport(ProximityReader)
        if let readError = error as? PaymentCardReaderSession.ReadError {
            return sessionLevelReadErrorNames.contains(String(describing: readError))
        }
    #endif

    let text = failureText(of: error)
    // Whole words, not substrings. No case name contains another today, so this
    // is not fixing a live collision; the text being searched is a human
    // readable description, and matching a name inside prose would be a wider
    // net than intended.
    return text
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .contains { sessionLevelReadErrorNames.contains(String($0)) }
}

/// The `ReadError` cases that mean the session is gone. The session survives
/// every other case, including `readerSessionBusy`, `readerSessionNetworkError`,
/// `readCancelled`, `cardReadFailed`, `paymentCardDeclined` and `nfcDisabled`.
private let sessionLevelReadErrorNames: Set<String> = [
    "noReaderSession",
    "readerSessionExpired",
    "readerTokenExpired",
    "readerSessionAuthenticationError"
]

/// The text to match against, preferring the reason carried by the SDK's own
/// error over a generic `localizedDescription`.
private func failureText(of error: Error) -> String {
    if let ttpError = error as? PayabliTTPError {
        switch ttpError {
        case let .nfcFailed(reason),
             let .readerSetupFailed(reason):
            return reason
        default:
            return String(describing: ttpError)
        }
    }
    return "\(String(describing: error)) \(error.localizedDescription)"
}
