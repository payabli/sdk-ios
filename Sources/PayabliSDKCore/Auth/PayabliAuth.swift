import Foundation

public actor PayabliAuth {
    private let config: PayabliConfig
    private let logger = PayabliLogger(category: .auth)

    private var currentToken: String
    /// Guards against concurrent refresh attempts. If a refresh is in flight,
    /// other callers await the same Task result.
    private var inFlightRefresh: Task<String, Error>?

    public init(config: PayabliConfig) {
        self.config = config
        self.currentToken = config.accessToken
    }

    /// Returns the current access token. Never throws synchronously — token
    /// refresh only happens after a 401 via `invalidateAndRefresh()`.
    public func currentAccessToken() -> String {
        currentToken
    }

    /// Marks the token as rejected and fetches a new one via `tokenProvider`.
    /// Callers should invoke this after receiving HTTP 401, then retry once.
    ///
    /// If no provider is configured, throws `PayabliGenericError(.tokenExpired)`
    /// so the caller can surface a re-authentication prompt.
    public func invalidateAndRefresh() async throws -> String {
        if let existing = inFlightRefresh {
            return try await existing.value
        }

        guard let provider = config.tokenProvider else {
            logger.error("Access token rejected and no tokenProvider configured")
            throw PayabliGenericError(
                code: .tokenExpired,
                reason: "Access token expired",
                detail: "Host app did not supply a tokenProvider; re-initialize the SDK with a fresh accessToken."
            )
        }

        let task = Task<String, Error> { [logger] in
            logger.info("Refreshing access token via partner tokenProvider")
            let fresh = try await provider()
            return fresh
        }
        inFlightRefresh = task

        do {
            let fresh = try await task.value
            currentToken = fresh
            inFlightRefresh = nil
            logger.info("Access token refreshed")
            return fresh
        } catch {
            inFlightRefresh = nil
            logger.error("Token refresh failed")
            throw PayabliGenericError(
                code: .tokenExpired,
                reason: "Token refresh failed",
                underlying: error
            )
        }
    }

    /// Test/dev convenience — resets the cached token to the initial value from
    /// `PayabliConfig`. Not part of the public API contract.
    public func reset() {
        currentToken = config.accessToken
        inFlightRefresh = nil
    }
}
