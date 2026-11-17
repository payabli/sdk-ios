import Foundation
import PayabliSDKCore

/// A card-present device route, named as its telemetry event names it.
enum DeviceRoute: String, Sendable {
    case challenge
    case register
    case attest
    case activate
    case config
}

/// The one client every card-present device route is sent through: the four attestation-family POSTs and the
/// configuration GET. The bearer and its refresh are the transport's.
final class DeviceRouteClient: Sendable {
    private let transport: any PayabliTransport
    private let logger = PayabliLogger(category: .taptopay)

    /// - Parameter transport: what every device route is sent over, the session's.
    init(transport: any PayabliTransport) {
        self.transport = transport
    }

    /// Sends a device-route GET and answers its raw response, for the caller to classify.
    ///
    /// - Parameter route: the route sent, which names the request in its logs.
    /// - Parameter request: the request, carrying its assertion headers.
    /// - Returns: the raw response.
    func get(_ route: DeviceRoute, _ request: PayabliRequest) async throws -> PayabliResponse {
        // The headers carry the App Attest assertion, key id and device id.
        logger.info("[\(route.rawValue)] → GET \(request.path)")
        let response = try await transport.perform(request)
        // A configuration body carries the card reader's credentials. The log gets its shape.
        logger.info("[\(route.rawValue)] ← [\(response.statusCode)] bytes=\(response.body.count)")
        return response
    }

    /// Sends a device-route POST with its assertion headers and maps the answer; the bearer and refresh are the transport's.
    ///
    /// - Parameter route: the route sent, which names the request in its logs.
    /// - Parameter path: the route the request is sent to.
    /// - Parameter body: the request's body, encoded as JSON.
    /// - Parameter assertion: the assertion headers to append, or `nil` where the route needs none.
    /// - Parameter readsRefusalBeforeStatus: reads a 400, 403 or 404's refusal envelope, or a 401 saying the binding is
    ///   gone, before the status mapping.
    /// - Parameter pinsCredential: sends a refused token once and throws ``PinnedTokenRefusal``.
    /// - Parameter makeDeclineError: builds the error a refusal or decline throws, from the code and reason the
    ///   service sent, or `nil` where the words name nothing the route classifies, so the status mapping answers.
    /// - Returns: the raw response, for the caller to decode.
    func post(
        _ route: DeviceRoute,
        path: String,
        body: some Encodable,
        assertion: AssertionHeaders?,
        readsRefusalBeforeStatus: Bool = false,
        pinsCredential: Bool = false,
        makeDeclineError: (_ code: Int?, _ reason: String) -> (any Error)?
    ) async throws -> PayabliResponse {
        var headers: [String: String] = [:]
        if let assertion {
            headers.merge(assertion.asDictionary) { _, new in new }
        }
        let request = try PayabliRequest.json(
            method: .post,
            path: path,
            headers: headers,
            jsonBody: body,
            pinsCredential: pinsCredential
        )

        // These bodies and headers are authentication material: `/activate`
        // carries the activation code, the others carry the App Attest key,
        // attestation and assertion. Endpoint and size only.
        logger.info("[\(route.rawValue)] → POST \(request.path) bytes=\(request.body?.count ?? 0)")

        let response: PayabliResponse
        do {
            response = try await transport.perform(request)
        } catch {
            // `AuthenticatedTransport` answers a spent token as a typed error, so
            // this catch is not only URLSession failures and not only Foundation's
            // words.
            logger.error("[\(route.rawValue)] transport error: \(ErrorSummary.of(error))")
            throw error
        }

        logger.info("[\(route.rawValue)] ← [\(response.statusCode)] bytes=\(response.body.count)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let (_, reason) = PayabliEnvelope.declineOutcome(from: response.body, decoder: decoder),
           let unregistered = AppRegistrationRefusals.hostError(status: response.statusCode, reason: reason)
        {
            logger.error("[\(route.rawValue)] refused: the app is not registered on the paypoint")
            throw unregistered
        }
        // Only the statuses a refusal is sent with. Every other status keeps the transport's own
        // classification, a rate limit's wait among them. A classifier that knows the words throws its own
        // failure; one that does not leaves the status mapping to answer.
        if readsRefusalBeforeStatus,
           let (code, reason) = PayabliEnvelope.declineOutcome(from: response.body, decoder: decoder),
           [400, 403, 404].contains(response.statusCode)
           || BindingRefusal.isBindingGone(code: response.statusCode, reason: reason)
        {
            if let decline = makeDeclineError(code ?? response.statusCode, reason) {
                logger.error("[\(route.rawValue)] refused (code=\(code.map(String.init) ?? "nil"))")
                throw DeviceRefusalStatus.carrying(response.statusCode, on: decline)
            }
        }
        if pinsCredential, response.statusCode == 401 {
            logger.error("[\(route.rawValue)] the token was refused")
            throw PinnedTokenRefusal()
        }

        do {
            try mapPayabliHTTPError(response: response)
        } catch {
            logger.error("[\(route.rawValue)] HTTP error: \(ErrorSummary.of(error))")
            throw error
        }

        if let (code, reason) = PayabliEnvelope.declineOutcome(from: response.body, decoder: decoder) {
            // The reason is the service's `resultText`, which can quote what was
            // sent. The code says which decline this was, and a classifier that
            // knows the words answers with its own failure.
            logger.error("[\(route.rawValue)] declined (code=\(code.map(String.init) ?? "nil"))")
            let decline = makeDeclineError(code, reason) ?? PayabliTTPError.attestationFailed(reason: reason)
            throw DeviceRefusalStatus.carrying(response.statusCode, on: decline)
        }

        return response
    }
}
