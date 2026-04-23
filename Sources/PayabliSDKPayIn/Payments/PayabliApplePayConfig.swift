import Foundation

#if canImport(PassKit)
import PassKit
#endif

/// Configuration for Apple Pay flows (PRD FR-10.2).
@objc public final class PayabliApplePayConfig: NSObject, Sendable {
    /// Apple-assigned merchant identifier (e.g. `"merchant.com.payabli.demo"`).
    public let merchantIdentifier: String

    /// ISO 3166-1 alpha-2 country code.
    public let countryCode: String

    /// ISO 4217 currency code.
    public let currencyCode: String

    /// Display name rendered in the payment sheet.
    public let merchantName: String

    /// Whether to support 3DS during Apple Pay authentication.
    public let supports3DS: Bool

    /// Authorization methods to request.
    public let authMethodsRaw: [String]

    /// Supported card networks as string identifiers (e.g. `"visa"`, `"masterCard"`).
    public let supportedNetworksRaw: [String]

    public init(
        merchantIdentifier: String,
        countryCode: String = "US",
        currencyCode: String = "USD",
        merchantName: String,
        supports3DS: Bool = true,
        supportedNetworks: [String] = ["visa", "masterCard", "amex", "discover"]
    ) {
        self.merchantIdentifier = merchantIdentifier
        self.countryCode = countryCode
        self.currencyCode = currencyCode
        self.merchantName = merchantName
        self.supports3DS = supports3DS
        self.supportedNetworksRaw = supportedNetworks
        self.authMethodsRaw = ["PAN_ONLY", "CRYPTOGRAM_3DS"]
    }

    #if canImport(PassKit)
    /// Resolves the configured network strings to `PKPaymentNetwork` values.
    public var supportedNetworks: [PKPaymentNetwork] {
        supportedNetworksRaw.compactMap { raw in
            switch raw.lowercased() {
            case "visa": return .visa
            case "mastercard", "master": return .masterCard
            case "amex", "americanexpress": return .amex
            case "discover": return .discover
            default: return nil
            }
        }
    }

    /// Merchant capabilities derived from the 3DS flag.
    public var merchantCapabilities: PKMerchantCapability {
        supports3DS ? .capability3DS : []
    }
    #endif
}

/// Abstraction of the Apple Pay token we forward to the Payabli API (PRD FR-10.4).
public struct ApplePayToken: Sendable {
    public let paymentData: Data
    public let network: String?
    public let displayName: String?

    public init(paymentData: Data, network: String?, displayName: String?) {
        self.paymentData = paymentData
        self.network = network
        self.displayName = displayName
    }
}
