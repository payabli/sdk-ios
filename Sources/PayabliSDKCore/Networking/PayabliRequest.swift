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

    package init(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        isCallerRefusal: @escaping @Sendable (PayabliResponse) -> Bool = { _ in false }
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
        self.isCallerRefusal = isCallerRefusal
    }

    /// Convenience for JSON POSTs with a `Content-Type: application/json` header.
    ///
    /// - Parameter method: the request's HTTP method, `POST` for the usual JSON send.
    /// - Parameter path: the route path, resolved against the environment's base URL.
    /// - Parameter query: the query items appended to the path.
    /// - Parameter headers: the request's own headers, where a `Content-Type` spelled exactly is replaced by the JSON one.
    /// - Parameter jsonBody: the body value, encoded as JSON with ISO-8601 dates.
    /// - Returns: the assembled request, ready for the decoration chain.
    package static func json(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        jsonBody: some Encodable
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
            body: body
        )
    }
}
