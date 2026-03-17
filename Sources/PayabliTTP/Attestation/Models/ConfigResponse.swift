import Foundation

/// Response from GET /api/v2/TapToPay/config
/// Contains the Fiserv credentials needed to initialize FiservTTPCardReader.
/// These are held in memory only -- never persisted to disk.
struct ConfigResponse: Decodable, CustomStringConvertible {
    let fiserv: FiservConfig
    let requestToken: String

    var description: String { "ConfigResponse(redacted)" }
}

struct FiservConfig: Decodable {
    let secretKey: String
    let apiKey: String
    let environment: String
    let currencyCode: String
    let merchantId: String
    let appleTtpMerchantId: String
    let merchantName: String
    let merchantCategoryCode: String
    let terminalId: String
    let terminalProfileId: String
}
