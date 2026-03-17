import Foundation

/// Unified error type for the PayabliTTP SDK.
/// Covers all failure domains: attestation, networking, backend, Fiserv, and SDK state.
public enum PayabliTTPError: LocalizedError, Sendable {
    case notInitialized
    case deviceNotSupported
    case attestationFailed(String)
    case networkError(String)
    case backendError(statusCode: Int, message: String)
    case decodingError(String)
    case fiservError(String)
    case sessionExpired
    case invalidState(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "PayabliTTP SDK has not been initialized. Call initialize() first."
        case .deviceNotSupported:
            return "This device does not support Tap to Pay."
        case .attestationFailed(let detail):
            return "Device attestation failed: \(detail)"
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .backendError(let code, let message):
            return "Backend error (\(code)): \(message)"
        case .decodingError(let detail):
            return "Failed to decode backend response: \(detail)"
        case .fiservError(let detail):
            return "Card reader error: \(detail)"
        case .sessionExpired:
            return "The NFC session has expired. Call reinitializeIfNeeded()."
        case .invalidState(let detail):
            return "Invalid SDK state: \(detail)"
        case .unknown(let detail):
            return "Unexpected error: \(detail)"
        }
    }
}
