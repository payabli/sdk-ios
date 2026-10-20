import Foundation
import PayabliSDKCore

/// The refusal `/activate` and `/config` send when the service holds no live attestation for the device the request
/// presented, so it has to be set up again. Both this and an expired token arrive as a 401, so only the text tells
/// them apart, and the text is sent without a final period.
enum BindingRefusal {
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
