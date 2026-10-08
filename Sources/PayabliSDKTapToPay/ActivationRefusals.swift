import Foundation
import PayabliSDKCore

/// Turns an `/activate` refusal into the catalog entry a host receives, by reading the service's own words.
///
/// The only place that reads an activation refusal's text, so the day the service stops telling its refusals
/// apart by text there is one file to rewrite. Every comparison is exact, or a prefix where the service appends
/// detail, and a refusal matching nothing reports `unknown`, which tells a host nothing it would act on wrongly.
///
/// A 401 never reaches this table: the transport answers it as an expired token. A 5xx keeps the service's
/// own error, and the wait it asked for.
enum ActivationRefusals {
    static func hostError(resultCode: Int?, reason: String) -> TapToPayError {
        let type = catalogType(resultCode: resultCode, reason: reason)
        return TapToPayError(type: type, reason: type.message, detail: reason.isEmpty ? nil : reason)
    }

    /// Whether the refusal says the service holds no record of the device, so the binding presented names
    /// nothing and setting the device up again needs it gone. A rejected assertion keeps it.
    static func discardsBinding(resultCode: Int?, reason: String) -> Bool {
        resultCode == 404 && reason == deviceNotFound
    }

    static func catalogType(resultCode: Int?, reason: String) -> PayabliErrorType {
        switch resultCode {
        case 400:
            return badRequestType(reason: reason)
        case 403 where reason == entryPointUnusable:
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
    private static let entryPointUnusable = "Entry point is not available for this request."

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
