import Foundation

/// HTTP client for Payabli APIs.
///
/// Pure transport layer — no auth state. Callers supply headers (including
/// `Authorization: Bearer <access token>`), and the service performs the
/// request, returning the raw response or a decoded envelope.
///
/// Error mapping (PRD §8 "Error Codes", §8.1.1):
/// - 400 → throws `PayabliPaymentError.validation`
/// - 401 → throws `PayabliGenericError(code: .tokenExpired)` (callers re-auth)
/// - 402 → throws `PayabliPaymentError.decline`
/// - 403 → throws `PayabliGenericError(code: .permissionDenied)`
/// - 410 → throws `PayabliGenericError(code: .sessionBurned)`
/// - 500 → throws `PayabliPaymentError.server`
/// - Other non-2xx → throws `PayabliGenericError(code: .unknown)`
public final class PayabliService: PayabliTransport, Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let logger: PayabliLogger

    /// Default per-request timeout (PRD NFR-6 — 10 seconds for tokenization calls).
    public static let defaultRequestTimeout: TimeInterval = 10

    public init(environment: PayabliEnvironment, session: URLSession? = nil) {
        self.baseURL = environment.baseURL
        self.session = session ?? Self.makeDefaultSession()
        self.logger = PayabliLogger(category: .network)
    }

    static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = defaultRequestTimeout
        config.timeoutIntervalForResource = defaultRequestTimeout * 3
        config.waitsForConnectivity = false
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }

    /// Performs an HTTP request. Returns the raw response; throws for transport
    /// failures or non-decodable responses.
    ///
    /// Callers should use `performV2` for envelope decoding, or decode the raw
    /// response body manually for non-v2 endpoints.
    public func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        let urlRequest = try buildURLRequest(request)
        logger.debug("→ \(request.method.rawValue) \(request.path)")

        do {
            let (data, urlResponse) = try await session.data(for: urlRequest)
            guard let http = urlResponse as? HTTPURLResponse else {
                throw PayabliGenericError(
                    code: .networkError,
                    reason: "Non-HTTP response"
                )
            }

            let headers = (http.allHeaderFields as? [String: String]) ?? [:]
            logger.debug("← \(request.method.rawValue) \(request.path) [\(http.statusCode)]")

            return PayabliResponse(
                statusCode: http.statusCode,
                headers: headers,
                body: data
            )
        } catch let error as PayabliGenericError {
            throw error
        } catch {
            logger.error("Network error on \(request.path): \(error.localizedDescription)")
            throw PayabliGenericError(
                code: .networkError,
                reason: "Network request failed",
                underlying: error
            )
        }
    }

    /// Performs a request and decodes a v2 (MoneyIn) envelope.
    public func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        let response = try await perform(request)
        try mapHTTPError(response: response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(PayabliV2Envelope<T>.self, from: response.body)
        } catch {
            throw PayabliGenericError(
                code: .decodingError,
                reason: "Failed to decode v2 envelope",
                underlying: error
            )
        }
    }

    // MARK: - Internals

    private func buildURLRequest(_ request: PayabliRequest) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(request.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw PayabliGenericError(code: .invalidConfiguration, reason: "Invalid URL")
        }
        if !request.query.isEmpty {
            components.queryItems = request.query
        }
        guard let url = components.url else {
            throw PayabliGenericError(code: .invalidConfiguration, reason: "Invalid URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = request.body
        return urlRequest
    }

    /// Maps a non-2xx `PayabliResponse` to a typed error. No-op for 2xx.
    /// Callers that decode responses manually (e.g. attestation endpoints
    /// that return a non-v2 envelope) should invoke this before decoding.
    public func mapHTTPError(response: PayabliResponse) throws {
        try mapPayabliHTTPError(response: response)
    }
}

// MARK: - Shared HTTP error mapping

/// Maps a non-2xx `PayabliResponse` to a typed error. No-op for 2xx.
///
/// The `override` closure receives the raw HTTP status code and may return a
/// component-specific error (e.g. `PayabliTTPError.devicePendingActivation`
/// for a 403 on the config endpoint). Return `nil` to fall through to the
/// standard mapping.
///
/// Standard mappings (PRD §8):
/// - 400 → `PayabliPaymentError.validation`, whatever the body says
/// - 401 → `PayabliGenericError(.tokenExpired)`
/// - 402 → `PayabliPaymentError.decline` (or `.generic(.unknown)`)
/// - 403 → `PayabliGenericError(.permissionDenied)`
/// - 410 → `PayabliGenericError(.sessionBurned)`
/// - 500+ → `PayabliPaymentError.server` (or `.generic(.unknown)`)
/// - other non-2xx → `PayabliGenericError(.unknown)`
public func mapPayabliHTTPError(
    response: PayabliResponse,
    override: ((Int) -> (any Error)?)? = nil
) throws {
    guard !(200 ..< 300).contains(response.statusCode) else { return }

    // Component-specific override takes priority.
    if let customError = override?(response.statusCode) {
        throw customError
    }

    let decoder = JSONDecoder()

    switch response.statusCode {
    case 400:
        // The status fixes the classification; the body only decides how many fields
        // get filled. A body that will not decode costs the fields, so a caller's
        // catch on `.validation` cannot miss because a proxy returned HTML. The
        // sibling platform states the same invariant on its own mapper.
        let validation = (try? decoder.decode(PayabliValidationError.self, from: response.body))
            ?? PayabliValidationError()
        throw PayabliPaymentError.validation(validation)

    case 401:
        throw PayabliGenericError(code: .tokenExpired, reason: "Unauthorized (401)")

    case 402:
        if let decline = try? decoder.decode(PayabliDeclineError.self, from: response.body) {
            throw PayabliPaymentError.decline(decline)
        }
        throw PayabliGenericError(code: .unknown, reason: "Payment declined (402)")

    case 403:
        throw PayabliGenericError(code: .permissionDenied, reason: "Forbidden (403)")

    case 410:
        throw PayabliGenericError(code: .sessionBurned, reason: "Session burned (410)")

    case 500...:
        if let server = try? decoder.decode(PayabliServerError.self, from: response.body) {
            throw PayabliPaymentError.server(server)
        }
        throw PayabliGenericError(code: .unknown, reason: "Server error (\(response.statusCode))")

    default:
        throw PayabliGenericError(
            code: .unknown,
            reason: "HTTP \(response.statusCode)"
        )
    }
}
