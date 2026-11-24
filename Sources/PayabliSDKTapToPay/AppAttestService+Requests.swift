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
            body: ChallengeRequest(entry: entry),
            readsRefusalBeforeStatus: true,
            isCredentialPinned: true,
            makeDeclineError: ColdRouteRefusals.decline
        )
    }

    func postRegister(_ body: RegisterRequest) async throws -> RegisterResponse {
        try await postAttestationRequest(
            .register,
            body: body,
            readsRefusalBeforeStatus: true,
            isCredentialPinned: true,
            makeDeclineError: ColdRouteRefusals.decline
        )
    }

    func postAttest(_ body: AttestRequest) async throws {
        try await postAttestationRequestExpectingNoBody(
            .attest,
            body: body,
            readsRefusalBeforeStatus: true,
            isCredentialPinned: true,
            makeDeclineError: ColdRouteRefusals.attestDecline
        )
    }

    /// Authenticated POST that expects a non-empty `responseData` of type `Payload`, and throws where the envelope holds none.
    ///
    /// - Parameter route: the route sent, which names the request in its logs and decode errors.
    /// - Parameter body: the request's body, encoded as JSON.
    /// - Parameter assertion: the assertion headers to append, or `nil` where the route needs none.
    /// - Parameter readsRefusalBeforeStatus: reads a 400, 403 or 404's refusal envelope, or a 401 saying the binding
    ///   is gone, before the status mapping.
    /// - Parameter isCredentialPinned: sends a refused token once and throws ``PinnedTokenRefusal``.
    /// - Parameter makeDeclineError: builds the error a refusal or decline throws, from the code and reason the
    ///   service sent, or `nil` where the words name nothing the route classifies.
    /// - Returns: the envelope's `responseData`, decoded as `Payload`.
    func postAttestationRequest<Payload: Decodable>(
        _ route: DeviceRoute,
        body: some Encodable,
        assertion: AssertionHeaders? = nil,
        readsRefusalBeforeStatus: Bool = false,
        isCredentialPinned: Bool = false,
        makeDeclineError: @escaping (_ code: Int?, _ reason: String) -> (any Error)? = { _, _ in nil }
    ) async throws -> Payload {
        try await routes.measured(route) {
            let response = try await routes.post(
                route,
                body: body,
                assertion: assertion,
                readsRefusalBeforeStatus: readsRefusalBeforeStatus,
                isCredentialPinned: isCredentialPinned,
                makeDeclineError: makeDeclineError
            )
            return try read(response, on: route)
        }
    }

    /// The envelope's `responseData`, decoded as `Payload`.
    ///
    /// - Parameter response: the route's answer, already read for a refusal.
    /// - Parameter route: the route answered, which names the answer in its logs and errors.
    /// - Returns: the decoded payload, or throws `decodingError` where it is missing or unreadable.
    private func read<Payload: Decodable>(_ response: PayabliResponse, on route: DeviceRoute) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let success = try decoder.decode(PayabliEnvelope.Success<Payload>.self, from: response.body)
            guard let payload = success.responseData else {
                throw undecodable(reason: "\(route.rawValue) missing responseData", statusCode: response.statusCode)
            }
            return payload
        } catch let error as TapToPayError {
            throw error
        } catch {
            logger.error("[\(route.rawValue)] payload decode failed: \(error.localizedDescription)")
            throw undecodable(reason: "Failed to decode \(route.rawValue) response", statusCode: response.statusCode)
        }
    }

    /// Authenticated POST for endpoints that answer with an `isSuccess` acknowledgement and no `responseData`.
    ///
    /// - Parameter route: the route sent, which names the request in its logs and errors.
    /// - Parameter body: the request's body, encoded as JSON.
    /// - Parameter assertion: the assertion headers to append, or `nil` where the route needs none.
    /// - Parameter readsRefusalBeforeStatus: hands a refusal envelope on a 400, 403 or 404, or a 401 saying the binding is
    ///   gone, to `makeDeclineError`, for a route whose refusals are told apart by their text rather than by their status.
    /// - Parameter isCredentialPinned: sends a refused token once and throws ``PinnedTokenRefusal``.
    /// - Parameter makeDeclineError: builds the error a refusal or decline throws, from the code and reason the
    ///   service sent, or `nil` where the words name nothing the route classifies.
    func postAttestationRequestExpectingNoBody(
        _ route: DeviceRoute,
        body: some Encodable,
        assertion: AssertionHeaders? = nil,
        readsRefusalBeforeStatus: Bool = false,
        isCredentialPinned: Bool = false,
        makeDeclineError: @escaping (_ code: Int?, _ reason: String) -> (any Error)? = { _, _ in nil }
    ) async throws {
        try await routes.measured(route) {
            let response = try await routes.post(
                route,
                body: body,
                assertion: assertion,
                readsRefusalBeforeStatus: readsRefusalBeforeStatus,
                isCredentialPinned: isCredentialPinned,
                makeDeclineError: makeDeclineError
            )
            try read(response, on: route)
        }
    }

    /// Throws `decodingError` unless the answer is an `isSuccess: true` envelope. One with no `responseData` is a success.
    ///
    /// - Parameter response: the route's answer, already read for a refusal.
    /// - Parameter route: the route answered, which names the answer in its logs and errors.
    private func read(_ response: PayabliResponse, on route: DeviceRoute) throws {
        let status = try? JSONDecoder().decode(PayabliEnvelope.Status.self, from: response.body)
        guard status?.isSuccess != true else { return }
        logger.error("[\(route.rawValue)] acknowledgement unreadable")
        throw undecodable(reason: "Failed to decode \(route.rawValue) response", statusCode: response.statusCode)
    }

    /// The failure for an answer that could not be used.
    ///
    /// - Parameter reason: what the error says.
    /// - Parameter statusCode: the answer's status.
    /// - Returns: the `decodingError` the caller throws.
    private func undecodable(reason: String, statusCode: Int) -> TapToPayError {
        TapToPayError(
            type: .decodingError,
            reason: reason,
            detail: nil,
            httpStatus: statusCode
        )
    }
}
