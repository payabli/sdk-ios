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

    var httpStatus: Int? {
        401
    }

    var reason: String {
        "Unauthorized (401)"
    }

    var detail: String? {
        nil
    }
}

/// Puts the refusing answer's status on a device or activation refusal, which carries no code.
enum DeviceRefusalStatus {
    /// - Parameter status: the status the refusing answer came with.
    /// - Parameter refusal: the refusal a route's classifier built from the answer's words.
    /// - Returns: the same refusal carrying `status`, or `refusal` unchanged when it is none of the refusal types.
    static func carrying(_ status: Int, on refusal: any Error) -> any Error {
        switch refusal {
        case let failure as PayabliTTPError:
            failure.carrying(httpStatus: status)
        case let activation as ActivationRefusal:
            ActivationRefusal(hostError: activation.hostError.carrying(httpStatus: status), movesSession: activation.movesSession)
        case let host as TapToPayError:
            host.carrying(httpStatus: status)
        default:
            refusal
        }
    }
}

/// A device route's failure, named by what the service answered rather than by the phase that sent the route.
///
/// One factory builds it from the refusal's code, read with HTTP's meanings, so the same answer is the same failure on
/// every route.
struct DeviceRouteRefusal: PayabliError {
    let type: PayabliErrorType
    let detail: String?
    let httpStatus: Int?
    let rawCode: String?

    var reason: String {
        type.message
    }

    /// Whether the service answered and said no, as opposed to an answer the route could not use.
    var isRefusal: Bool {
        type != .serverError && type != .decodingError
    }

    /// The failure a refusal no route classifier recognises is reported as.
    ///
    /// - Parameter code: the code the refusal named, or `nil` when it named none.
    /// - Parameter reason: the service's words, kept as the detail.
    /// - Parameter httpStatus: the status the refusal came with.
    /// - Returns: 400 is the SDK's own defect, 401 a device to set up again, 403 an activation owed, 404 a refused entry
    ///   point, 5xx the service failing, and any other code, or none, unknown.
    static func of(code: Int?, reason: String, httpStatus: Int) -> DeviceRouteRefusal {
        let type: PayabliErrorType = switch code {
        case 400: .sdkInternalError
        case 401: .deviceSetupRequired
        case 403: .devicePendingActivation
        case 404: .entryPointRefused
        case let .some(code) where code >= 500: .serverError
        default: .unknown
        }
        return DeviceRouteRefusal(type: type, detail: reason, httpStatus: httpStatus, rawCode: code.map(String.init))
    }

    /// A success the route could not read, or one carrying nothing the route needs.
    ///
    /// - Parameter httpStatus: the status the answer came with.
    /// - Returns: a decoding failure, which carries no excerpt of what was rejected.
    static func undecodable(httpStatus: Int) -> DeviceRouteRefusal {
        DeviceRouteRefusal(type: .decodingError, detail: nil, httpStatus: httpStatus, rawCode: nil)
    }
}
