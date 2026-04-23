import Foundation

/// v2 response envelope used by MoneyIn APIs.
///
/// ```json
/// {
///   "code": "A...",
///   "reason": "...",
///   "explanation": "...",
///   "action": "...",
///   "data": { ... }
/// }
/// ```
///
/// See PRD §8.2 "v2 envelope". Success: `code.hasPrefix("A")`.
///
/// The SDK intentionally ignores any envelope-level `token` field — every
/// authenticated request reuses the access token held by `PayabliAuth`.
public struct PayabliV2Envelope<Data: Decodable>: Decodable {
    public let code: String
    public let reason: String?
    public let explanation: String?
    public let action: String?
    public let data: Data?

    /// `true` if `code` starts with `"A"` (Approved family).
    public var isApproved: Bool { code.hasPrefix("A") }

    /// `true` if `code` starts with `"D"` (Declined family).
    public var isDeclined: Bool { code.hasPrefix("D") }
}
