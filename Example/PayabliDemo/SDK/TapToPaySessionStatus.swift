import PayabliSDKTapToPay

/// Where the card reader has got to, in this app's own words.
///
/// These mirror the SDK's states, plus a case for one it adds later, so a screen
/// switches over this and not over a type that can grow under it.
enum TapToPaySessionStatus {
    case idle
    case attestingDevice
    case fetchingConfig
    case initializingReader
    case ready
    case sessionExpired
    case reinitializing
    case pendingActivation
    case pendingTerms
    case charging(TapToPayChargeStep)
    case error
    case unrecognised(Int)

    /// The short form a status chip shows.
    var label: String {
        switch self {
        case .idle: return "idle"
        case .attestingDevice: return "attesting"
        case .fetchingConfig: return "config"
        case .initializingReader: return "reader"
        case .ready: return "ready"
        case .sessionExpired: return "expired"
        case .reinitializing: return "reinit"
        case .pendingActivation: return "pending"
        case .pendingTerms: return "terms"
        case let .charging(step): return step.label
        case .error: return "error"
        case let .unrecognised(raw): return "state(\(raw))"
        }
    }

    /// How a status reads, so the app picks the colour and this does not import a
    /// palette.
    var severity: TapToPayStatusSeverity {
        switch self {
        case .ready: return .ready
        case .error, .sessionExpired: return .failed
        case .pendingActivation, .pendingTerms: return .waiting
        default: return .working
        }
    }

    /// Whether the reader can take a tap.
    var acceptsTap: Bool {
        self == .ready
    }

    /// Whether a charge holds the reader.
    var isCharging: Bool {
        if case .charging = self {
            return true
        }
        return false
    }
}

/// What a running charge is doing, in this app's own words.
enum TapToPayChargeStep: Equatable {
    case opening
    case waitingForCard
    case closing
    case cardDetected
    case removeCard
    case tryAgain
    case enterPIN
    case pinEntered
    case promptDismissed
    case unrecognised(Int)

    var label: String {
        switch self {
        case .opening: return "Opening payment"
        case .waitingForCard: return "Tap a card"
        case .closing: return "Closing payment"
        case .cardDetected: return "Reading card"
        case .removeCard: return "Remove the card"
        case .tryAgain: return "Tap the card again"
        case .enterPIN: return "Enter the PIN"
        case .pinEntered: return "PIN entered"
        case .promptDismissed: return "Prompt closed"
        case let .unrecognised(raw): return "charging(\(raw))"
        }
    }
}

/// What a status means for the reader, without saying how to draw it.
enum TapToPayStatusSeverity {
    case ready
    case failed
    case waiting
    case working
}

extension TapToPaySessionStatus: Equatable {}

extension TapToPaySessionStatus {
    init(_ state: PayabliTTPSessionState) {
        switch state {
        case .idle: self = .idle
        case .attestingDevice: self = .attestingDevice
        case .fetchingConfig: self = .fetchingConfig
        case .initializingReader: self = .initializingReader
        case .ready: self = .ready
        case .sessionExpired: self = .sessionExpired
        case .reinitializing: self = .reinitializing
        case .pendingActivation: self = .pendingActivation
        case .pendingTerms: self = .pendingTerms
        case .failed: self = .error
        case let .charging(activity): self = .charging(TapToPayChargeStep(activity))
        // The SDK ships as a resilient binary framework, so a host built against
        // this version can be handed a case added by a later one.
        @unknown default: self = .unrecognised(state.code.rawValue)
        }
    }
}

extension TapToPayChargeStep {
    init(_ activity: TapToPayChargeActivity) {
        switch activity {
        case .opening: self = .opening
        case .waitingForCard: self = .waitingForCard
        case .closing: self = .closing
        case .cardDetected: self = .cardDetected
        case .cardRemovalRequested: self = .removeCard
        case .cardReadRetryRequested: self = .tryAgain
        case .pinEntryRequested: self = .enterPIN
        case .pinEntryCompleted: self = .pinEntered
        case .readerPromptDismissed: self = .promptDismissed
        @unknown default: self = .unrecognised(activity.rawValue)
        }
    }
}
