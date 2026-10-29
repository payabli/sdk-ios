import Foundation

/// ``PayabliErrorType`` for Objective-C, which cannot see a `String`-backed Swift enum. Each raw value is the
/// catalog number, the `NSError` code of every SDK error in the `com.payabli.ttp`, `com.payabli.payIn` and
/// `com.payabli.session` domains, so a host compares that code against a named case.
///
/// Raw values are public API: do not reorder or renumber.
@objc public enum PayabliErrorTypeCode: Int, Sendable, CaseIterable {
    case missingToken = 1001
    case tokenExpired = 1002
    case tokenMalformed = 1003
    case tokenProviderFailed = 1004
    case invalidSignature = 1005
    case permissionDenied = 1006
    case sessionBurned = 1007
    case paymentDeclined = 1008
    case serverError = 1009
    case rateLimited = 1010
    case conflict = 1011
    case invalidConfiguration = 1012
    case networkError = 1013
    case decodingError = 1014
    case userCancelled = 1015
    case validation = 1016
    case unknown = 1017
    case sdkInternalError = 1018
    case sessionNotInitialized = 1019
    case transactionNotFound = 1020
    case retryRefused = 1021
    case retryNotSamePayment = 1022
    case paymentReferenceOpen = 1023
    case deviceKeyUnavailable = 3001
    case deviceSetupUnsupported = 3002
    case deviceServicesOutdated = 3003
    case devicePendingActivation = 3004
    case deviceSetupRequired = 3005
    case deviceSetupRefused = 3006
    case deviceSetupUnavailable = 3007
    case deviceSetupNotConfigured = 3008
    case entryPointRefused = 3009
    case readerCredentialsUnusable = 3010
    case deviceOSUnsupported = 3011
    case deviceHardwareUnsupported = 3012
    case termsNotAccepted = 3013
    case cardPresentNotEnabled = 3014
    case readerDeviceRefused = 3015
    case readerUnavailable = 3016
    case readerSessionExpired = 3017
    case tapNotCompleted = 3018
    case paymentNotOpened = 3019
    case cardDeclined = 3020
    case paymentOutcomeUnknown = 3021
    case paymentNotClosed = 3022
    case activationCodeMalformed = 3023
    case activationCodeIncorrect = 3024
    case activationCodeExpired = 3025
    case activationAttemptsExhausted = 3026
    case activationCodeNotIssued = 3027
    case deviceNotPending = 3028
    case terminalNotReady = 3029
    case tooManyOpenCharges = 3030
    case paymentNotHeld = 3031
    case deviceIdentityUnavailable = 3033
    case chargeNotFinished = 3034
    case paymentNotTaken = 3035
    case contactlessDisabled = 3036
}
