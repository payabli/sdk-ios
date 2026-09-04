import Foundation

/// A pending HTTP request assembled by the SDK.
///
/// Consumed by `PayabliService`, which resolves it against the environment base URL, runs the
/// decoration chain over it, and performs the call. The chain sets the credential, and overrides an
/// `Authorization` header set here.
public struct PayabliRequest: Sendable {
    public static let contentTypeHeader = "Content-Type"
    public static let applicationJSON = "application/json"

    public let method: HTTPMethod
    public let path: String
    public let query: [URLQueryItem]
    public let headers: [String: String]
    public let body: Data?

    public init(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// Convenience for JSON POSTs with a `Content-Type: application/json` header.
    public static func json(
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
