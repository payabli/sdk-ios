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
            label: "attest"
        )
    }

    /// Authenticated POST that expects a non-empty `responseData` of type
    /// `Payload`. Throws if the envelope is missing it.
    func postAttestationRequest<Body: Encodable, Payload: Decodable>(
        path: String,
        body: Body,
        label: String,
        assertion: AssertionHeaders? = nil,
        makeDeclineError: @escaping (_ code: Int?, _ reason: String) -> PayabliTTPError = { _, reason in
            .attestationFailed(reason: reason)
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
                throw PayabliTTPError.attestationFailed(reason: "\(label) missing responseData")
            }
            return payload
        } catch let error as PayabliTTPError {
            throw error
        } catch {
            logger.error("[\(label)] payload decode failed: \(error.localizedDescription)")
            throw PayabliTTPError.attestationFailed(reason: "Failed to decode \(label) response")
        }
    }

    /// Authenticated POST for endpoints that do not return a `responseData`
    /// body (only an `isSuccess` acknowledgement).
    func postAttestationRequestExpectingNoBody<Body: Encodable>(
        path: String,
        body: Body,
        label: String,
        assertion: AssertionHeaders? = nil,
        makeDeclineError: @escaping (_ code: Int?, _ reason: String) -> PayabliTTPError = { _, reason in
            .attestationFailed(reason: reason)
        }
    ) async throws {
        _ = try await performAuthenticatedPOST(
            path: path,
            body: body,
            label: label,
            assertion: assertion,
            makeDeclineError: makeDeclineError
        )
    }

    // MARK: - Private plumbing

    /// Bearer + (optional) assertion headers, logging, HTTP error mapping, and
    /// the "HTTP 200 with `isSuccess: false`" decline check. Returns the raw
    /// response so the two public variants above can decide how to decode.
    ///
    /// Bearer injection and 401 refresh-and-retry are handled by the
    /// `transport` decorator (`AuthenticatedTransport`); this method only
    /// appends the App Attest assertion headers that are specific to the
    /// attestation/activation endpoint family.
    private func performAuthenticatedPOST<Body: Encodable>(
        path: String,
        body: Body,
        label: String,
        assertion: AssertionHeaders?,
        makeDeclineError: (_ code: Int?, _ reason: String) -> PayabliTTPError
    ) async throws -> PayabliResponse {
        var headers: [String: String] = [:]
        if let assertion {
            headers.merge(assertion.asDictionary) { _, new in new }
        }
        let request = try PayabliRequest.json(
            method: .post,
            path: path,
            headers: headers,
            jsonBody: body
        )

        let headersDump = request.headers
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: " | ")
        let bodyDump = request.body.flatMap { String(data: $0, encoding: .utf8) } ?? "<nil>"
        logger.info("[\(label)] → POST \(request.path)")
        logger.info("[\(label)] headers: \(headersDump)")
        logger.info("[\(label)] body: \(bodyDump)")

        let response: PayabliResponse
        do {
            response = try await transport.perform(request)
        } catch {
            logger.error("[\(label)] transport error: \(error.localizedDescription)")
            throw error
        }

        let responseBody = String(data: response.body, encoding: .utf8) ?? "<non-utf8 \(response.body.count) bytes>"
        logger.info("[\(label)] ← [\(response.statusCode)] body: \(responseBody)")

        do {
            try mapPayabliHTTPError(response: response)
        } catch {
            logger.error("[\(label)] HTTP error: \(error.localizedDescription)")
            throw error
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let (code, reason) = PayabliEnvelope.declineOutcome(from: response.body, decoder: decoder) {
            logger.error("[\(label)] declined (code=\(code.map(String.init) ?? "nil")): \(reason)")
            throw makeDeclineError(code, reason)
        }

        return response
    }
}
