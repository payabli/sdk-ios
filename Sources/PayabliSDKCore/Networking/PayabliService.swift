import Foundation

/// HTTP client for Payabli APIs.
///
/// The decoration chain is built in the initializer and applied as the first statement of `perform`,
/// so every request through this type is decorated. `AuthenticatedTransport` wraps this and adds 401
/// recovery; a request that skips that wrapper still carries its credential.
///
/// Error mapping, which ``mapPayabliHTTPError`` performs and states in full:
/// - 400 → throws `PayabliPaymentError.validation`
/// - 401 → throws `PayabliGenericError(code: .tokenExpired)` (callers re-auth)
/// - 402 → throws `PayabliPaymentError.decline`
/// - 403 → throws `PayabliGenericError(code: .permissionDenied)`
/// - 409 → throws `PayabliGenericError(code: .conflict)`
/// - 410 → throws `PayabliGenericError(code: .sessionBurned)`
/// - 429 → throws `PayabliGenericError(code: .rateLimited)`
/// - 500 → throws `PayabliPaymentError.server`
/// - Other non-2xx → throws `PayabliGenericError(code: .unknown)`
package final class PayabliService: PayabliTransport, Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let logger: PayabliLogger
    private let decorations: [any PayabliRequestDecoration]

    /// Default per-request timeout (PRD NFR-6 — 10 seconds for tokenization calls).
    package static let defaultRequestTimeout: TimeInterval = 10

    /// The only way to build a transport outside this module.
    ///
    /// There is no initializer that takes a chain, so every transport carries the one the factory
    /// builds. `readToken` reaches the chain and nothing here reads it; it is called once per request,
    /// so a rotation needs no cache invalidated.
    package convenience init(
        environment: PayabliEnvironment,
        readToken: @escaping @Sendable () async throws -> String,
        session: URLSession? = nil
    ) {
        self.init(
            environment: environment,
            decorations: RequestDecorationFactory.chain(readToken: readToken),
            session: session,
            logger: PayabliLogger(category: .network)
        )
    }

    private init(
        environment: PayabliEnvironment,
        decorations: [any PayabliRequestDecoration],
        session: URLSession?,
        logger: PayabliLogger
    ) {
        self.baseURL = environment.baseURL
        self.session = session ?? Self.makeDefaultSession()
        self.logger = logger
        self.decorations = decorations
    }

    /// Builds a transport carrying the shipping chain, with the caller's logger.
    ///
    /// Internal, so it widens what a test can construct and not what production can. The chain is the
    /// one the public initializer builds, because a test that reads what this layer logged still has to
    /// be running the decorations that attach the credential.
    static func makeWithChain(
        environment: PayabliEnvironment,
        readToken: @escaping @Sendable () async throws -> String,
        session: URLSession? = nil,
        logger: PayabliLogger
    ) -> PayabliService {
        PayabliService(
            environment: environment,
            decorations: RequestDecorationFactory.chain(readToken: readToken),
            session: session,
            logger: logger
        )
    }

    /// Builds a transport with a caller-supplied chain, for a test that needs a specific one.
    ///
    /// Internal, so it widens what a test can construct and not what production can. Not for a
    /// shipping code path.
    static func makeWithDecorations(
        environment: PayabliEnvironment,
        decorations: [any PayabliRequestDecoration],
        session: URLSession? = nil,
        logger: PayabliLogger
    ) -> PayabliService {
        PayabliService(
            environment: environment,
            decorations: decorations,
            session: session,
            logger: logger
        )
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
    package func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        // First statement, so no path through this method skips decoration.
        let decorated = try await decorations.applyTo(request)
        let urlRequest = try buildURLRequest(decorated)
        logger.debug("→ \(decorated.method.rawValue) \(decorated.path)")

        do {
            let (data, urlResponse) = try await session.data(for: urlRequest)
            guard let http = urlResponse as? HTTPURLResponse else {
                throw PayabliGenericError(
                    code: .networkError,
                    reason: "Non-HTTP response"
                )
            }

            let headers = (http.allHeaderFields as? [String: String]) ?? [:]
            logger.debug("← \(decorated.method.rawValue) \(decorated.path) [\(http.statusCode)]")

            return PayabliResponse(
                statusCode: http.statusCode,
                headers: headers,
                body: data
            )
        } catch let error as PayabliGenericError {
            throw error
        } catch {
            logger.error("Network error on \(decorated.path): \(error.localizedDescription)")
            throw PayabliGenericError(
                code: .networkError,
                reason: "Network request failed",
                underlying: error
            )
        }
    }

    /// Performs a request and decodes a v2 (MoneyIn) envelope.
    package func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        let response = try await perform(request)
        try mapHTTPError(response: response)
        return try decodePayabliV2Envelope(T.self, from: response)
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
    package func mapHTTPError(response: PayabliResponse) throws {
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
/// Standard mappings:
/// - 400 → `PayabliPaymentError.validation`
/// - 401 → `PayabliGenericError(.tokenExpired)`
/// - 402 → `PayabliPaymentError.decline`
/// - 403 → `PayabliGenericError(.permissionDenied)`
/// - 409 → `PayabliGenericError(.conflict)`
/// - 410 → `PayabliGenericError(.sessionBurned)`
/// - 429 → `PayabliGenericError(.rateLimited)`
/// - 500+ → `PayabliPaymentError.server`
/// - other non-2xx → `PayabliGenericError(.unknown)`
///
/// The status fixes the classification; the body only decides how many fields get filled.
package func mapPayabliHTTPError(
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
        let validation = (try? decoder.decode(PayabliValidationError.self, from: response.body))
            ?? PayabliValidationError()
        throw PayabliPaymentError.validation(validation)

    case 401:
        throw PayabliGenericError(code: .tokenExpired, reason: "Unauthorized (401)")

    case 402:
        let decline = (try? decoder.decode(PayabliDeclineError.self, from: response.body))
            ?? PayabliDeclineError()
        throw PayabliPaymentError.decline(decline)

    case 403:
        throw PayabliGenericError(code: .permissionDenied, reason: "Forbidden (403)")

    case 409:
        throw PayabliGenericError(code: .conflict, reason: "Conflict (409)")

    case 410:
        throw PayabliGenericError(code: .sessionBurned, reason: "Session burned (410)")

    case 429:
        throw PayabliGenericError(code: .rateLimited, reason: "Too many requests (429)")

    case 500...:
        let server = (try? decoder.decode(PayabliServerError.self, from: response.body))
            ?? PayabliServerError()
        throw PayabliPaymentError.server(server)

    default:
        throw PayabliGenericError(
            code: .unknown,
            reason: "HTTP \(response.statusCode)"
        )
    }
}
