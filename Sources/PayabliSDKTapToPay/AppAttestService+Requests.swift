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
            .challenge,
            path: "/api/v2/device/taptopay/challenge",
            body: ChallengeRequest(entry: entry),
            readsRefusalBeforeStatus: true,
            pinsCredential: true,
            makeDeclineError: ColdRouteRefusals.decline
        )
    }

    func postRegister(_ body: RegisterRequest) async throws -> RegisterResponse {
        try await postAttestationRequest(
            .register,
            path: "/api/v2/device/taptopay/register",
            body: body,
            readsRefusalBeforeStatus: true,
            pinsCredential: true,
            makeDeclineError: ColdRouteRefusals.decline
        )
    }

    func postAttest(_ body: AttestRequest) async throws {
        try await postAttestationRequestExpectingNoBody(
            .attest,
            path: "/api/v2/device/taptopay/attest",
            body: body,
            readsRefusalBeforeStatus: true,
            pinsCredential: true,
            makeDeclineError: ColdRouteRefusals.attestDecline
        )
    }

    /// Authenticated POST that expects a non-empty `responseData` of type `Payload`, and throws where the envelope holds none.
    ///
    /// - Parameter route: the route sent, which names the request in its logs and decode errors.
    /// - Parameter path: the route the request is sent to.
    /// - Parameter body: the request's body, encoded as JSON.
    /// - Parameter assertion: the assertion headers to append, or `nil` where the route needs none.
    /// - Parameter readsRefusalBeforeStatus: reads a 400, 403 or 404's refusal envelope, or a 401 saying the binding
    ///   is gone, before the status mapping.
    /// - Parameter pinsCredential: sends a refused token once and throws ``PinnedTokenRefusal``.
    /// - Parameter makeDeclineError: builds the error a refusal or decline throws, from the code and reason the
    ///   service sent, or `nil` where the words name nothing the route classifies.
    /// - Returns: the envelope's `responseData`, decoded as `Payload`.
    func postAttestationRequest<Payload: Decodable>(
        _ route: DeviceRoute,
        path: String,
        body: some Encodable,
        assertion: AssertionHeaders? = nil,
        readsRefusalBeforeStatus: Bool = false,
        pinsCredential: Bool = false,
        makeDeclineError: @escaping (_ code: Int?, _ reason: String) -> (any Error)? = { _, reason in
            PayabliTTPError.attestationFailed(reason: reason)
        }
    ) async throws -> Payload {
        try await routes.measured(route) {
            let response = try await routes.post(
                route,
                path: path,
                body: body,
                assertion: assertion,
                readsRefusalBeforeStatus: readsRefusalBeforeStatus,
                pinsCredential: pinsCredential,
                makeDeclineError: makeDeclineError
            )
            return try decodedPayload(of: response, on: route)
        }
    }

    /// The envelope's `responseData`, decoded as `Payload`.
    ///
    /// - Parameter response: the route's answer, already read for a refusal.
    /// - Parameter route: the route answered, which names the answer in its logs and errors.
    /// - Returns: the decoded payload, or throws `decodingError` where it is missing or unreadable.
    private func decodedPayload<Payload: Decodable>(of response: PayabliResponse, on route: DeviceRoute) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let success = try decoder.decode(PayabliEnvelope.Success<Payload>.self, from: response.body)
            guard let payload = success.responseData else {
                throw TapToPayError(
                    type: .decodingError,
                    reason: "\(route.rawValue) missing responseData",
                    detail: nil,
                    httpStatus: response.statusCode
                )
            }
            return payload
        } catch let error as TapToPayError {
            throw error
        } catch {
            logger.error("[\(route.rawValue)] payload decode failed: \(error.localizedDescription)")
            throw TapToPayError(
                type: .decodingError,
                reason: "Failed to decode \(route.rawValue) response",
                detail: nil,
                httpStatus: response.statusCode
            )
        }
    }

    /// Authenticated POST for endpoints that answer with an `isSuccess` acknowledgement and no `responseData`.
    ///
    /// - Parameter route: the route sent, which names the request in its logs and errors.
    /// - Parameter path: the route the request is sent to.
    /// - Parameter body: the request's body, encoded as JSON.
    /// - Parameter assertion: the assertion headers to append, or `nil` where the route needs none.
    /// - Parameter readsRefusalBeforeStatus: hands a refusal envelope on a 400, 403 or 404, or a 401 saying the binding is
    ///   gone, to `makeDeclineError`, for a route whose refusals are told apart by their text rather than by their status.
    /// - Parameter pinsCredential: sends a refused token once and throws ``PinnedTokenRefusal``.
    /// - Parameter makeDeclineError: builds the error a refusal or decline throws, from the code and reason the
    ///   service sent, or `nil` where the words name nothing the route classifies.
    func postAttestationRequestExpectingNoBody(
        _ route: DeviceRoute,
        path: String,
        body: some Encodable,
        assertion: AssertionHeaders? = nil,
        readsRefusalBeforeStatus: Bool = false,
        pinsCredential: Bool = false,
        makeDeclineError: @escaping (_ code: Int?, _ reason: String) -> (any Error)? = { _, reason in
            PayabliTTPError.attestationFailed(reason: reason)
        }
    ) async throws {
        try await routes.measured(route) {
            let response = try await routes.post(
                route,
                path: path,
                body: body,
                assertion: assertion,
                readsRefusalBeforeStatus: readsRefusalBeforeStatus,
                pinsCredential: pinsCredential,
                makeDeclineError: makeDeclineError
            )
            try requireAcknowledgement(in: response, on: route)
        }
    }

    /// Throws `decodingError` unless the answer is an `isSuccess: true` envelope. One with no `responseData` is a success.
    ///
    /// - Parameter response: the route's answer, already read for a refusal.
    /// - Parameter route: the route answered, which names the answer in its logs and errors.
    private func requireAcknowledgement(in response: PayabliResponse, on route: DeviceRoute) throws {
        let status = try? JSONDecoder().decode(PayabliEnvelope.Status.self, from: response.body)
        guard status?.isSuccess != true else { return }
        logger.error("[\(route.rawValue)] acknowledgement unreadable")
        throw TapToPayError(
            type: .decodingError,
            reason: "Failed to decode \(route.rawValue) response",
            detail: nil,
            httpStatus: response.statusCode
        )
    }
}
