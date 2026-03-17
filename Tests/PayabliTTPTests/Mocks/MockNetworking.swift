import Foundation
@testable import PayabliTTP

final class MockNetworking: Networking {

    let configuration: PayabliTTPConfiguration

    /// Queue of responses to return. Each call to execute() pops the first element.
    var responses: [Any] = []
    var shouldFail: Error?
    var executeCalled = 0
    var executeVoidCalled = 0

    init(configuration: PayabliTTPConfiguration? = nil) {
        self.configuration = configuration ?? PayabliTTPConfiguration(
            apiKey: "test-api-key",
            entry: "test-entry",
            deviceId: "test-device-id",
            environment: .qa,
            logLevel: .none
        )
    }

    func buildRequest(
        endpoint: Endpoint,
        authHeader: (field: String, value: String)
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://test.payabli.com\(endpoint.path)")!)
        request.httpMethod = endpoint.method
        request.setValue(authHeader.value, forHTTPHeaderField: authHeader.field)
        return request
    }

    func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        executeCalled += 1
        if let error = shouldFail { throw error }
        guard !responses.isEmpty, let value = responses.removeFirst() as? T else {
            throw PayabliTTPError.decodingError("No mock response queued for type \(T.self)")
        }
        return value
    }

    func executeVoid(_ request: URLRequest) async throws {
        executeVoidCalled += 1
        if let error = shouldFail { throw error }
    }

    func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }
}
