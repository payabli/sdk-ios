import Foundation
import PayabliSDKCore

// MARK: - Attestation networking helpers

//
// Concrete-endpoint wrappers (`postChallenge`, `postRegister`, `postAttest`)
// plus the shared machinery used by every authenticated POST in the
// attestation/activation family.

extension AppAttestService {
    func postChallenge(entry: String) async throws -> ChallengeResponse {
        try await postAttestationRequest(
            path: "/api/v2/device/taptopay/challenge",
            body: ChallengeRequest(entry: entry),
            label: "challenge"
        )
    }

    func postRegister(_ body: RegisterRequest) async throws -> RegisterResponse {
        try await postAttestationRequest(
            path: "/api/v2/device/taptopay/register",
            body: body,
            label: "register"
        )
    }

    func postAttest(_ body: AttestRequest) async throws {
        try await postAttestationRequestExpectingNoBody(
            path: "/api/v2/device/taptopay/attest",
            body: body,
            label: "attest",
            pinsCredential: true
        )
    }

    /// Authenticated POST that expects a non-empty `responseData` of type
    /// `Payload`. Throws if the envelope is missing it.
    ///
    /// - Parameter path: the route the request is sent to.
    /// - Parameter body: the request's body, encoded as JSON.
    /// - Parameter label: the request's name, carried by its logs and decode errors.
    /// - Parameter assertion: the assertion headers to append, or `nil` where the route needs none.
    /// - Parameter makeDeclineError: builds the error a refusal or decline throws, from the code and reason the service sent.
    /// - Returns: the envelope's `responseData`, decoded as `Payload`.
    func postAttestationRequest<Payload: Decodable>(
        path: String,
        body: some Encodable,
        label: String,
        assertion: AssertionHeaders? = nil,
        makeDeclineError: @escaping (_ code: Int?, _ reason: String) -> any Error = { _, reason in
            PayabliTTPError.attestationFailed(reason: reason)
        }
    ) async throws -> Payload {
        let response = try await performAuthenticatedPOST(
            path: path,
            body: body,
            label: label,
            assertion: assertion,
            makeDeclineError: makeDeclineError
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let success = try decoder.decode(PayabliEnvelope.Success<Payload>.self, from: response.body)
            guard let payload = success.responseData else {
                throw TapToPayError(type: .decodingError, reason: "\(label) missing responseData", detail: nil)
            }
            return payload
        } catch let error as TapToPayError {
            throw error
        } catch {
            logger.error("[\(label)] payload decode failed: \(error.localizedDescription)")
            throw TapToPayError(type: .decodingError, reason: "Failed to decode \(label) response", detail: nil)
        }
    }

    /// Authenticated POST for endpoints that answer with an `isSuccess` acknowledgement and no `responseData`.
    ///
    /// - Parameter path: the route the request is sent to.
    /// - Parameter body: the request's body, encoded as JSON.
    /// - Parameter label: the request's name, carried by its logs and errors.
    /// - Parameter assertion: the assertion headers to append, or `nil` where the route needs none.
    /// - Parameter readsRefusalBeforeStatus: hands a refusal envelope on a 400, 403 or 404, or a 401 saying the binding is
    ///   gone, to `makeDeclineError`, for a route whose refusals are told apart by their text rather than by their status.
    /// - Parameter pinsCredential: sends a refused token once and throws ``PinnedTokenRefusal``.
    /// - Parameter makeDeclineError: builds the error a refusal or decline throws, from the code and reason the service sent.
    func postAttestationRequestExpectingNoBody(
        path: String,
        body: some Encodable,
        label: String,
        assertion: AssertionHeaders? = nil,
        readsRefusalBeforeStatus: Bool = false,
        pinsCredential: Bool = false,
        makeDeclineError: @escaping (_ code: Int?, _ reason: String) -> any Error = { _, reason in
            PayabliTTPError.attestationFailed(reason: reason)
        }
    ) async throws {
        _ = try await performAuthenticatedPOST(
            path: path,
            body: body,
            label: label,
            assertion: assertion,
            readsRefusalBeforeStatus: readsRefusalBeforeStatus,
            pinsCredential: pinsCredential,
            makeDeclineError: makeDeclineError
        )
    }

    // MARK: - Private plumbing

    /// Sends an attestation-family POST with its assertion headers and maps the answer: a refusal envelope, a pinned 401,
    /// an HTTP error, or a 200 carrying `isSuccess: false`. The bearer and any refresh are the transport's.
    ///
    /// - Parameter path: the route the request is sent to.
    /// - Parameter body: the request's body, encoded as JSON.
    /// - Parameter label: the request's name, carried by its logs and errors.
    /// - Parameter assertion: the assertion headers to append, or `nil` where the route needs none.
    /// - Parameter readsRefusalBeforeStatus: reads a 400, 403 or 404's refusal envelope, or a 401 saying the binding is
    ///   gone, before the status mapping.
    /// - Parameter pinsCredential: sends a refused token once and throws ``PinnedTokenRefusal``.
    /// - Parameter makeDeclineError: builds the error a refusal or decline throws, from the code and reason the service sent.
    /// - Returns: the raw response, for the caller to decode.
    private func performAuthenticatedPOST(
        path: String,
        body: some Encodable,
        label: String,
        assertion: AssertionHeaders?,
        readsRefusalBeforeStatus: Bool = false,
        pinsCredential: Bool = false,
        makeDeclineError: (_ code: Int?, _ reason: String) -> any Error
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
        logger.info("[\(label)] → POST \(request.path) bytes=\(request.body?.count ?? 0)")

        let response: PayabliResponse
        do {
            response = try await transport.perform(request)
        } catch {
            // `AuthenticatedTransport` answers a spent token as a typed error, so
            // this catch is not only URLSession failures and not only Foundation's
            // words.
            logger.error("[\(label)] transport error: \(ErrorSummary.of(error))")
            throw error
        }

        logger.info("[\(label)] ← [\(response.statusCode)] bytes=\(response.body.count)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Only the statuses a refusal is sent with. Every other status keeps the transport's own
        // classification, a rate limit's wait among them.
        if readsRefusalBeforeStatus,
           let (code, reason) = PayabliEnvelope.declineOutcome(from: response.body, decoder: decoder),
           [400, 403, 404].contains(response.statusCode)
           || BindingRefusal.isBindingGone(code: response.statusCode, reason: reason)
        {
            logger.error("[\(label)] refused (code=\(code.map(String.init) ?? "nil"))")
            throw makeDeclineError(code ?? response.statusCode, reason)
        }
        if pinsCredential, response.statusCode == 401 {
            logger.error("[\(label)] the token was refused")
            throw PinnedTokenRefusal()
        }

        do {
            try mapPayabliHTTPError(response: response)
        } catch {
            logger.error("[\(label)] HTTP error: \(ErrorSummary.of(error))")
            throw error
        }

        if let (code, reason) = PayabliEnvelope.declineOutcome(from: response.body, decoder: decoder) {
            // The reason is the service's `resultText`, which can quote what was
            // sent. The code says which decline this was.
            logger.error("[\(label)] declined (code=\(code.map(String.init) ?? "nil"))")
            throw makeDeclineError(code, reason)
        }

        return response
    }
}
