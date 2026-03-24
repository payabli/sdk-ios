import Foundation

public struct PayabliTTPConfiguration: Sendable {

    public let apiKey: String
    public let entry: String
    public let deviceId: String
    /// iOS App ID in the format "TEAM_ID.BUNDLE_ID" (e.g. "ABC123DEF4.com.partner.myapp").
    /// Used by the backend to verify the rpIdHash in the Apple App Attest CBOR.
    /// Will be replaced by server-side config (PaypointApps table) in a future release.
    public let appId: String
    public let environment: PayabliTTPEnvironment
    public let logLevel: LogLevel

    public init(
        apiKey: String,
        entry: String,
        deviceId: String,
        appId: String,
        environment: PayabliTTPEnvironment = .production,
        logLevel: LogLevel = .none
    ) {
        precondition(!apiKey.isEmpty, "PayabliTTP: apiKey must not be empty")
        precondition(!entry.isEmpty, "PayabliTTP: entry must not be empty")
        precondition(!deviceId.isEmpty, "PayabliTTP: deviceId must not be empty")
        precondition(!appId.isEmpty, "PayabliTTP: appId must not be empty")

        self.apiKey = apiKey
        self.entry = entry
        self.deviceId = deviceId
        self.appId = appId
        self.environment = environment
        self.logLevel = logLevel
    }

    var baseURL: URL {
        environment.baseURL
    }
}
