import Foundation
import PayabliSDKCore

/// The refusal `/activate` and `/config` send when the service holds no live attestation for the device the request
/// presented, so it has to be set up again. Both this and an expired token arrive as a 401, so only the text tells
/// them apart, and the text is sent without a final period.
enum BindingRefusal {
    static let text = "Device not attested or attestation revoked"

    /// Whether a refusal says the binding is gone, whether its 401 arrived as the HTTP status or inside the envelope.
    ///
    /// - Parameter code: the HTTP status, or the envelope's `resultCode`.
    /// - Parameter reason: the envelope's `resultText`.
    /// - Returns: true only for a 401 carrying exactly ``text``.
    static func isBindingGone(code: Int?, reason: String) -> Bool {
        code == 401 && reason == text
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
