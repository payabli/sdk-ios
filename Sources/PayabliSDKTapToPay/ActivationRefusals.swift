import Foundation
import PayabliSDKCore

/// Turns an `/activate` refusal into the catalog entry a host receives, by reading the service's own words.
///
/// The only place that reads an activation refusal's text, so the day the service stops telling its refusals
/// apart by text there is one file to rewrite. Every comparison is exact, or a prefix where the service appends
/// detail, and a refusal matching nothing reports `unknown`, which tells a host nothing it would act on wrongly.
///
/// A 401 is not classified here: the activation drops the binding it presented for every 401, which makes
/// setting the device up again the remedy whatever the text says.
enum ActivationRefusals {
    static func hostError(resultCode: Int?, reason: String) -> TapToPayError {
        let type = catalogType(resultCode: resultCode, reason: reason)
        return TapToPayError(type: type, reason: type.message, detail: reason.isEmpty ? nil : reason)
    }

    static func catalogType(resultCode: Int?, reason: String) -> PayabliErrorType {
        switch resultCode {
        case 400:
            return badRequestType(reason: reason)
        case 403 where reason == entryPointUnusable:
            return .entryPointRefused
        case 404 where reason == deviceNotFound:
            return .deviceSetupRequired
        case 404 where reason.hasPrefix(paypointNotFoundPrefix):
            return .entryPointRefused
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
        case notPending:
            return .deviceNotPending
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
    private static let notPending = "Device is not pending activation."
    private static let assertionFailedPrefix = "Assertion verification failed: "
    private static let deviceNotFound = "Device not found."
    private static let paypointNotFoundPrefix = "Paypoint '"
    private static let entryPointUnusable = "Entry point is not available for this request."

    /// The fixed body and header complaints, each one a request this SDK built wrong.
    private static let malformedRequest: Set<String> = [
        "entry is required in the request body.",
        "deviceId is required in the request body.",
        "activationCode is required in the request body.",
        "X-App-Assertion header is required.",
        "X-App-KeyId header is required.",
        "X-Assertion-Timestamp header is required."
    ]
}
