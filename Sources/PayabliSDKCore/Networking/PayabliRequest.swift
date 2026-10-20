import Foundation

/// A pending HTTP request assembled by the SDK.
///
/// Consumed by `PayabliService`, which resolves it against the environment base URL, runs the
/// decoration chain over it, and performs the call. The chain sets the credential, and overrides an
/// `Authorization` header set here.
package struct PayabliRequest: Sendable {
    package static let contentTypeHeader = "Content-Type"
    package static let applicationJSON = "application/json"

    package let method: HTTPMethod
    package let path: String
    package let query: [URLQueryItem]
    package let headers: [String: String]
    package let body: Data?
    /// Whether a refused answer refuses this caller rather than its credential. True means the answer is
    /// returned as it arrived, with no refresh and no replay.
    package let isCallerRefusal: @Sendable (PayabliResponse) -> Bool
    /// Whether a credential rejection is returned as it arrived, with no refresh and no replay, because the route
    /// holds only for the credential it was sent. The refused token is kept for the caller to renew.
    package let pinsCredential: Bool

    package init(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        isCallerRefusal: @escaping @Sendable (PayabliResponse) -> Bool = { _ in false },
        pinsCredential: Bool = false
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
        self.isCallerRefusal = isCallerRefusal
        self.pinsCredential = pinsCredential
    }

    /// Convenience for JSON POSTs with a `Content-Type: application/json` header.
    package static func json(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        jsonBody: some Encodable,
        pinsCredential: Bool = false
    ) throws -> PayabliRequest {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(jsonBody)
        var mergedHeaders = headers
        mergedHeaders[contentTypeHeader] = applicationJSON
        return PayabliRequest(
            method: method,
            path: path,
            query: query,
            headers: mergedHeaders,
            body: body,
            pinsCredential: pinsCredential
        )
    }
}
