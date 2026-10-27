import Foundation
#if canImport(ProximityReader)
    import ProximityReader
#endif

/// Whether the reader session is gone, or only this read failed.
///
/// A dead session needs a fresh config and a reader re-prepare; a failed read needs neither. The set is
/// Apple's, from `PaymentCardReaderSession.ReadError`; where the type does not survive, only the case name arrives, in text.
///
/// - Parameter error: the failure the read ended with, typed or rebuilt as text.
/// - Returns: whether the session is gone with it.
func readerFailureInvalidatesSession(_ error: Error) -> Bool {
    if case PayabliTTPError.readerDeviceRefused = error {
        // The processor refused the device, and it will refuse the next read the same way until a fresh
        // config arms a new reader session.
        return true
    }
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
///
/// - Parameter error: the failure whose text is matched.
/// - Returns: the SDK error's reason where it carries one, or the failure described generically.
private func failureText(of error: Error) -> String {
    if let ttpError = error as? PayabliTTPError {
        switch ttpError {
        case let .nfcFailed(reason, _),
             let .readerSetupFailed(reason, _):
            return reason
        default:
            return String(describing: ttpError)
        }
    }
    return "\(String(describing: error)) \(error.localizedDescription)"
}
