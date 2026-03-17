import Foundation

public enum AttestationState: Sendable {
    case notRegistered
    case registered(keyId: String)
    case unsupported
}
