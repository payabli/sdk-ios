import Foundation
import PayabliSDKCore

/// Client for `POST /api/TokenStorage/add`.
///
/// See PRD §8 "Tokenization Endpoint".
///
/// 401 handling: on first 401, calls `auth.invalidateAndRefresh()` to obtain
/// a fresh token from the partner's backend, then retries exactly once. A
/// second 401 propagates to the caller as `.tokenExpired`.
public final class TokenStorageClient: Sendable {
    private let service: PayabliService
    private let auth: PayabliAuth
    private let logger = PayabliLogger(category: .tokenization)

    public init(service: PayabliService, auth: PayabliAuth) {
        self.service = service
        self.auth = auth
    }

    public func tokenizeCard(_ request: CardTokenizationRequest) async throws -> String {
        try await tokenize(request: request, query: [])
    }

    public func tokenizeACH(_ request: ACHTokenizationRequest) async throws -> String {
        try await tokenize(
            request: request,
            query: [URLQueryItem(name: "achValidation", value: "true")]
        )
    }

    public func tokenizeApplePay(_ request: ApplePayTokenizationRequest) async throws -> String {
        try await tokenize(request: request, query: [])
    }

    // MARK: - Internals

    private func tokenize(
        request body: some Encodable,
        query: [URLQueryItem]
    ) async throws -> String {
        try await withAuthRetry { token in
            let httpRequest = try PayabliRequest.json(
                method: .post,
                path: "/api/TokenStorage/add",
                query: query,
                headers: ["Authorization": "Bearer \(token)"],
                jsonBody: body
            )
            let response = try await service.perform(httpRequest)
            if (200..<300).contains(response.statusCode) {
                return try extractToken(from: response.body)
            }
            try mapFailure(response)
            // Unreachable — mapFailure always throws.
            throw PayabliGenericError(code: .unknown, reason: "Unreachable")
        }
    }

    /// Runs `operation` with the current access token. On 401, refreshes the
    /// token (via partner backend) and retries exactly once.
    private func withAuthRetry(
        _ operation: @Sendable (_ token: String) async throws -> String
    ) async throws -> String {
        let firstToken = await auth.currentAccessToken()
        do {
            return try await operation(firstToken)
        } catch let err as PayabliGenericError where err.code == .tokenExpired {
            logger.info("401 received — refreshing token and retrying once")
            let refreshed = try await auth.invalidateAndRefresh()
            return try await operation(refreshed)
        }
    }

    private func extractToken(from data: Data) throws -> String {
        if let envelope = try? JSONDecoder().decode(TokenizationResponse.self, from: data),
           let token = envelope.resolvedToken, !token.isEmpty {
            return token
        }
        if let bare = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"\n ")),
           !bare.isEmpty {
            return bare
        }
        logger.error("Tokenization response did not contain a token")
        throw PayabliGenericError(
            code: .decodingError,
            reason: "Tokenization response missing token"
        )
    }

    private func mapFailure(_ response: PayabliResponse) throws {
        let decoder = JSONDecoder()
        if response.statusCode == 400,
           let validation = try? decoder.decode(PayabliValidationError.self, from: response.body) {
            throw PayabliPaymentError.validation(validation)
        }
        if response.statusCode == 401 {
            throw PayabliGenericError(code: .tokenExpired, reason: "Token expired (401)")
        }
        if response.statusCode == 403 {
            throw PayabliGenericError(code: .permissionDenied, reason: "Forbidden (403)")
        }
        if response.statusCode >= 500,
           let server = try? decoder.decode(PayabliServerError.self, from: response.body) {
            throw PayabliPaymentError.server(server)
        }
        throw PayabliGenericError(
            code: .unknown,
            reason: "Tokenization failed",
            detail: "HTTP \(response.statusCode)"
        )
    }
}
