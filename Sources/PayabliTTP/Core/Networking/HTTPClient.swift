import Foundation

/// Adapter: Networking backed by URLSession.
/// Handles request building, execution, status validation, and error parsing.
/// Has zero knowledge of specific endpoints or business logic.
final class HTTPClient: Networking {

    let configuration: PayabliTTPConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: PayabliTTPConfiguration) {
        self.configuration = configuration
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Public request builders

    /// Build a URLRequest for the given endpoint with a single auth header.
    func buildRequest(
        endpoint: Endpoint,
        authHeader: (field: String, value: String)
    ) throws -> URLRequest {
        var url = configuration.baseURL.appendingPathComponent(endpoint.path)

        if case .config(let entry) = endpoint {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw PayabliTTPError.invalidState("Failed to build URL components for \(endpoint.path)")
            }
            components.queryItems = [URLQueryItem(name: "entry", value: entry)]
            guard let resolved = components.url else {
                throw PayabliTTPError.invalidState("Failed to resolve URL for \(endpoint.path)")
            }
            url = resolved
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        if endpoint.method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(authHeader.value, forHTTPHeaderField: authHeader.field)
        return request
    }

    // MARK: - Execution

    /// Execute request and decode JSON response body into `T`.
    func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await performRequest(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PayabliTTPError.decodingError(error.localizedDescription)
        }
    }

    /// Execute request where we only care about success/failure.
    func executeVoid(_ request: URLRequest) async throws {
        _ = try await performRequest(request)
    }

    /// Encode an `Encodable` value to JSON Data.
    func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    // MARK: - Internal

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PayabliTTPError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PayabliTTPError.networkError("Invalid response type")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let detail = parseErrorDetail(from: data)
            throw PayabliTTPError.backendError(
                statusCode: httpResponse.statusCode,
                message: detail
            )
        }

        return (data, httpResponse)
    }

    private func parseErrorDetail(from data: Data) -> String {
        struct ErrorBody: Decodable {
            let detail: String?
            let title: String?
        }
        if let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            return parsed.detail ?? parsed.title ?? "Unknown error"
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}
