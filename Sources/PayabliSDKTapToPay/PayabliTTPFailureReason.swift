import Foundation

/// Why a session failed, in terms of what can be done about it.
///
/// Two failures a host repairs the same way are one member here.
///
/// An enum, and not the error: this value is retained in a state read long after
/// the call that produced it, and an `Error` carries a cause chain that can hold
/// a response body. The error still reaches the caller that was waiting, by
/// being thrown.
public enum PayabliTTPFailureReason: Int, Sendable, CaseIterable {
    /// The device's proof of identity is gone or was refused, so the session
    /// must be built from the top.
    ///
    /// A repair does not attest, so it cannot restore this.
    case attestationRequired = 0

    /// The paypoint, the device or its gateway is not set up for card-present
    /// work. Someone changes the account; repeating the call will not.
    case configurationRejected = 1

    /// The service could not be reached, or failed inside. The same call may
    /// succeed later.
    case serviceUnavailable = 2

    /// This handset cannot take contactless payments as it stands, and nothing
    /// the app does reaches it.
    ///
    /// The remedy is a different handset where the hardware or the OS version is
    /// what is missing, and a change on the card reader vendor's side where the
    /// vendor is what refused it. The two arrive here alike.
    case deviceIneligible = 3

    /// The SDK and the service disagree about the contract, or the SDK has a
    /// defect. A failure inside the service is ``serviceUnavailable``.
    case sdkInternalError = 4
}
