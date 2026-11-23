import Foundation
import PayabliSDKCore

/// Turns an `/activate` refusal into the catalog entry a host receives, by the service's own words: each comparison is
/// exact, or a prefix where the service appends detail, and one matching nothing reports `unknown`. A binding that is gone (any
/// envelope 401) and an unregistered app (`AppRegistrationRefusals`) are read before it; a 5xx keeps its own error.
enum ActivationRefusals {
    static func refusal(resultCode: Int?, reason: String) -> ActivationRefusal {
        ActivationRefusal(
            hostError: hostError(resultCode: resultCode, reason: reason),
            movesSession: movesSession(resultCode: resultCode, reason: reason)
        )
    }

    /// A refusal at 400, 403 or 404 whose envelope named another code. Its words say nothing reliable, so it is
    /// classified without them and leaves the session waiting for its code.
    ///
    /// - Parameter status: the HTTP status the refusal came with.
    /// - Returns: `SDK_INTERNAL_ERROR` at 400 and `UNKNOWN` otherwise, carrying `status` and moving nothing.
    static func readByStatus(_ status: Int) -> any Error {
        let type: PayabliErrorType = status == 400 ? .sdkInternalError : .unknown
        let refusal = ActivationRefusal(
            hostError: TapToPayError(type: type, reason: type.message, detail: nil),
            movesSession: false
        )
        return DeviceRefusalStatus.carrying(status, on: refusal)
    }

    /// A 401 whose envelope named another code: the service holds no attestation for the key, so the session lands
    /// by the refusal.
    ///
    /// - Parameter refusal: the route's refusal, read by its status.
    /// - Returns: `DEVICE_SETUP_REQUIRED` carrying the refusal's status, moving the session.
    static func deviceRefused(_ refusal: DeviceRouteRefusal) -> any Error {
        let type = refusal.type
        let moved = ActivationRefusal(
            hostError: TapToPayError(type: type, reason: type.message, detail: nil),
            movesSession: true
        )
        guard let status = refusal.httpStatus else { return moved }
        return DeviceRefusalStatus.carrying(status, on: moved)
    }

    static func hostError(resultCode: Int?, reason: String) -> TapToPayError {
        let type = catalogType(resultCode: resultCode, reason: reason)
        return TapToPayError(type: type, reason: type.message, detail: reason.isEmpty ? nil : reason)
    }

    /// Whether the refusal says the service holds no record of the device, so the binding presented names
    /// nothing and setting the device up again needs it gone. A rejected assertion keeps it.
    ///
    /// - Parameter resultCode: the HTTP status the service refused the activation with.
    /// - Parameter reason: the service's refusal text, matched exactly against its fixed words.
    /// - Returns: whether the stored binding has to be dropped before the device can be set up again.
    static func discardsBinding(resultCode: Int?, reason: String) -> Bool {
        resultCode == 404 && reason == deviceNotFound
    }

    /// Whether the refusal says something about the session as well as the call: the device is unknown, or the
    /// entry point cannot be used. Every other refusal leaves the session waiting for its code.
    ///
    /// - Parameter resultCode: the HTTP status the service refused the activation with.
    /// - Parameter reason: the service's refusal text, matched exactly against its fixed words.
    /// - Returns: whether the session should move off the state it waited in.
    static func movesSession(resultCode: Int?, reason: String) -> Bool {
        discardsBinding(resultCode: resultCode, reason: reason)
            || (resultCode == 403 && reason == ColdRouteRefusals.entryPointUnusable)
    }

    static func catalogType(resultCode: Int?, reason: String) -> PayabliErrorType {
        switch resultCode {
        case 400:
            return badRequestType(reason: reason)
        case 403 where reason == ColdRouteRefusals.entryPointUnusable:
            return .entryPointRefused
        case 403 where reason == notPending:
            return .deviceNotPending
        case 404 where reason == deviceNotFound:
            return .deviceSetupRequired
        case let .some(code) where code >= 500:
            return .serverError
        default:
            return .unknown
        }
    }

    private static func badRequestType(reason: String) -> PayabliErrorType {
        switch reason {
        case invalidCode:
            return .activationCodeIncorrect
        case codeExpired:
            return .activationCodeExpired
        case tooManyAttempts:
            return .activationAttemptsExhausted
        case noChallenge, storedCodeInvalid:
            return .activationCodeNotIssued
        case _ where reason.hasPrefix(assertionFailedPrefix):
            return .deviceSetupRequired
        case _ where malformedRequest.contains(reason):
            return .sdkInternalError
        default:
            return .unknown
        }
    }

    private static let invalidCode = "Invalid activation code."
    private static let codeExpired = "Activation code has expired. Request a new challenge."
    private static let tooManyAttempts = "Too many failed activation attempts. Request a new challenge."
    private static let noChallenge = "No active challenge for this device."
    private static let storedCodeInvalid = "Stored activation code is invalid."
    private static let notPending = "Device is not in a state that allows this operation."
    private static let assertionFailedPrefix = "Assertion verification failed: "
    private static let deviceNotFound = "Device not found."

    /// The fixed body and header complaints, each one a request this SDK built wrong.
    private static let malformedRequest: Set<String> = [
        "entry is required in the request body.",
        "deviceId is required in the request body.",
        "activationCode is required in the request body.",
        "X-App-Assertion header is required.",
        "X-App-KeyId header is required.",
        "X-Assertion-Timestamp header is required.",
        "X-App-Assertion is not valid base64."
    ]
}

/// An `/activate` refusal, classified. A host receives `hostError`; `movesSession` says whether the session
/// lands by it or stays where it is.
struct ActivationRefusal: Error {
    let hostError: TapToPayError
    let movesSession: Bool
}
