import Foundation

/// Port: HTTP transport layer.
/// Production adapter: HTTPClient (URLSession).
/// Test adapter: MockHTTPClient (returns canned responses).
protocol Networking {
    var configuration: PayabliTTPConfiguration { get }

    func buildRequest(
        endpoint: Endpoint,
        authHeader: (field: String, value: String)
    ) throws -> URLRequest

    func execute<T: Decodable>(_ request: URLRequest) async throws -> T
    func executeVoid(_ request: URLRequest) async throws
    func encode<T: Encodable>(_ value: T) throws -> Data
}
