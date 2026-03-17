import Foundation

public struct PayabliTTPConfiguration: Sendable {

    public let apiKey: String
    public let entry: String
    public let deviceId: String
    public let environment: PayabliTTPEnvironment
    public let logLevel: LogLevel

    public init(
        apiKey: String,
        entry: String,
        deviceId: String,
        environment: PayabliTTPEnvironment = .production,
        logLevel: LogLevel = .none
    ) {
        precondition(!apiKey.isEmpty, "PayabliTTP: apiKey must not be empty")
        precondition(!entry.isEmpty, "PayabliTTP: entry must not be empty")
        precondition(!deviceId.isEmpty, "PayabliTTP: deviceId must not be empty")

        self.apiKey = apiKey
        self.entry = entry
        self.deviceId = deviceId
        self.environment = environment
        self.logLevel = logLevel
    }

    var baseURL: URL {
        environment.baseURL
    }
}
