import Foundation
#if canImport(ProximityReader)
import ProximityReader
#endif

/// Whether a reader failure means the reader session itself is gone, rather
/// than that one read did not succeed.
///
/// The two need separating because the remedies are opposite. A dead session is
/// only repaired by fetching a fresh config and preparing the reader again, and
/// a session left marked usable can never be repaired at all. A read that failed
/// on a live session needs none of that, and tearing the session down after a
/// declined card or a dismissed sheet would spend a round trip to fix nothing.
///
/// `PaymentCardReaderSession.ReadError` draws exactly this line, so the set
/// below is Apple's rather than one invented here.
///
/// Two tiers, because the typed value does not always survive. The card-reader
/// component catches the read error and rebuilds it as a title plus a
/// description, so by the time a charge fails on a device the type is gone and
/// only the case name remains in the text. The typed check runs first because it
/// cannot be fooled; the text check is what actually fires in production.
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

/// The `PaymentCardReaderSession.ReadError` cases that mean the session is no
/// longer usable. Every other case describes a read, not a session.
///
/// Deliberately excluded, because they are transient or specific to one read
/// and the session survives them: `readerSessionBusy`,
/// `readerSessionNetworkError`, `readCancelled`, `cardReadFailed`,
/// `paymentReadFailed`, `paymentCardDeclined`, `nfcDisabled`, the `pin` cases.
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
        case .nfcFailed(let reason),
             .readerSetupFailed(let reason):
            return reason
        default:
            return String(describing: ttpError)
        }
    }
    return "\(String(describing: error)) \(error.localizedDescription)"
}
