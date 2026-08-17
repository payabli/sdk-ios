import Foundation

// MARK: - Legacy "isSuccess / responseData" envelope

//
// Used by the `/api/v2/device/...` family (attestation, activation) and by
// `/api/v2/device/taptopay/config/{entry}`. Business-level failures come back
// as HTTP 200 + `isSuccess: false` with the reason carried inside
// `responseData.resultCode` / `resultText`, so every caller has to peek at
// `isSuccess` before committing to a full decode.
//
// The `PayabliV2Envelope` (below) is a different shape used by the MoneyIn
// APIs. Don't conflate them.

/// Envelope types and helpers shared by all "legacy" Payabli endpoints that
/// surface business-level failures as HTTP 200 + `isSuccess: false`.
///
/// ```swift
/// if let (code, reason) = PayabliEnvelope.declineOutcome(from: body) {
///     // Decline path — caller maps `code` to the domain-specific error.
/// } else {
///     let success = try decoder.decode(
///         PayabliEnvelope.Success<MyPayload>.self, from: body
///     )
///     ...
/// }
/// ```
public enum PayabliEnvelope {
    /// Thin "peek" of the response body: only `isSuccess` and the top-level
    /// `responseText`. Used to decide between the success and decline decodes
    /// without committing to the full payload shape.
    public struct Status: Decodable, Sendable {
        public let isSuccess: Bool?
        public let responseText: String?
    }

    /// `responseData.resultCode` / `responseData.resultText` on decline.
    public struct DeclinePayload: Decodable, Sendable {
        public let resultCode: Int?
        public let resultText: String?
    }

    /// Wrapper that pulls the `DeclinePayload` out of `responseData` on
    /// `isSuccess == false`.
    public struct DeclineEnvelope: Decodable, Sendable {
        public let responseData: DeclinePayload?
    }

    /// Wrapper that pulls the endpoint-specific payload out of `responseData`
    /// on `isSuccess == true`.
    public struct Success<Payload: Decodable>: Decodable {
        public let responseData: Payload?
    }

    /// Placeholder payload for endpoints that return no success body (e.g.
    /// `/attest` just returns `isSuccess: true`).
    public struct EmptyPayload: Decodable, Sendable {}

    /// Returns `(code, reason)` when `data` is a decline body
    /// (HTTP 200 + `isSuccess == false`), or `nil` when it looks like a
    /// success. `reason` falls back through decline text → top-level
    /// `responseText` → `"server declined"` so the caller always has a
    /// non-empty message.
    ///
    /// Uses `try?` decodes so a malformed body simply returns `nil`; the
    /// caller's subsequent `Success<Payload>` decode will produce the
    /// canonical "failed to decode response" error.
    public static func declineOutcome(
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) -> (code: Int?, reason: String)? {
        guard
            let status = try? decoder.decode(Status.self, from: data),
            status.isSuccess == false
        else {
            return nil
        }
        let decline = try? decoder.decode(DeclineEnvelope.self, from: data)
        let reason = decline?.responseData?.resultText
            ?? status.responseText
            ?? "server declined"
        return (decline?.responseData?.resultCode, reason)
    }
}

// MARK: - MoneyIn v2 envelope

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
    public var isApproved: Bool {
        code.hasPrefix("A")
    }

    /// `true` if `code` starts with `"D"` (Declined family).
    public var isDeclined: Bool {
        code.hasPrefix("D")
    }
}
