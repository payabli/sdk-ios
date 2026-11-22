import Foundation
import PayabliSDKCore

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
        case let route as DeviceRouteRefusal:
            DeviceRouteRefusal(type: route.type, detail: route.detail, httpStatus: status, resultCode: route.resultCode)
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
    /// The envelope's `resultCode`, reported in telemetry. A device route's code is its status, so it is not the
    /// error's `rawCode`.
    let resultCode: Int?

    var rawCode: String? {
        nil
    }

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
        return DeviceRouteRefusal(type: type, detail: reason, httpStatus: httpStatus, resultCode: code)
    }

    /// A success the route could not read, or one carrying nothing the route needs.
    ///
    /// - Parameter httpStatus: the status the answer came with.
    /// - Returns: a decoding failure, which carries no excerpt of what was rejected.
    static func undecodable(httpStatus: Int) -> DeviceRouteRefusal {
        DeviceRouteRefusal(type: .decodingError, detail: nil, httpStatus: httpStatus, resultCode: nil)
    }
}
