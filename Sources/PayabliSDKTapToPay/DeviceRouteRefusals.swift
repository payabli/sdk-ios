import Foundation
import PayabliSDKCore

/// The refusal `/activate` and `/config` send when the service holds no live attestation for the key and device the
/// request presented, so the binding names nothing and the device has to be set up again.
///
/// Told apart from an expired token by its text alone, because both arrive as a 401.
enum BindingRefusal {
    /// Sent without a final period.
    static let text = "Device not attested or attestation revoked"

    /// Whether a response with `statusCode` and `reason` says the binding is gone.
    ///
    /// - Parameter statusCode: the HTTP status the refusal arrived with.
    /// - Parameter reason: the envelope's `resultText`.
    /// - Returns: true only for a 401 carrying exactly ``text``.
    static func isBindingGone(statusCode: Int, reason: String) -> Bool {
        statusCode == 401 && reason == text
    }
}

/// A device route that pins its credential answered a plain 401: the token itself was refused.
///
/// The session sequence renews the token and runs once more, so this lands nowhere. A caller outside the sequence sees
/// 1002 `TOKEN_EXPIRED`, the same as any expired token.
struct PinnedTokenRefusal: PayabliError {
    var type: PayabliErrorType {
        .tokenExpired
    }

    var reason: String {
        "Unauthorized (401)"
    }

    var detail: String? {
        nil
    }
}
