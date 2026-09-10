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
        case .error: self = .error
        @unknown default: self = .unrecognised(state.rawValue)
        }
    }
}
