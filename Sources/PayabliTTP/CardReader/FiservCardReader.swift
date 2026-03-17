import Foundation
import FiservTTP
import Combine

/// Adapter: CardReading backed by Fiserv's FiservTTPCardReader.
/// Configured dynamically with credentials fetched from the backend.
final class FiservCardReader: CardReading {

    private var reader: FiservTTPCardReader?
    private var sessionReadyCancellable: AnyCancellable?
    private(set) var isSessionActive: Bool = false

    // MARK: - CardReading

    func configure(with config: ConfigResponse) throws {
        let env = Self.mapEnvironment(config.fiserv.environment)

        let fiservConfig = FiservTTPConfig(
            secretKey: config.fiserv.secretKey,
            apiKey: config.fiserv.apiKey,
            environment: env,
            currencyCode: config.fiserv.currencyCode,
            merchantId: config.fiserv.merchantId,
            appleTtpMerchantId: config.fiserv.appleTtpMerchantId,
            merchantName: config.fiserv.merchantName,
            merchantCategoryCode: config.fiserv.merchantCategoryCode,
            terminalId: config.fiserv.terminalId,
            terminalProfileId: config.fiserv.terminalProfileId
        )

        let newReader = FiservTTPCardReader(configuration: fiservConfig)

        sessionReadyCancellable = newReader.sessionReadySubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                self?.isSessionActive = ready
            }

        reader = newReader
    }

    func requestSessionToken() async throws {
        guard let reader else { throw PayabliTTPError.notInitialized }
        try await reader.requestSessionToken()
    }

    func isAccountLinked() async throws -> Bool {
        guard let reader else { throw PayabliTTPError.notInitialized }
        return try await reader.isAccountLinked()
    }

    func linkAccount() async throws {
        guard let reader else { throw PayabliTTPError.notInitialized }
        try await reader.linkAccount()
    }

    func initializeSession() async throws {
        guard let reader else { throw PayabliTTPError.notInitialized }
        try await reader.initializeSession()
        isSessionActive = true
    }

    /// Executes a sale charge via NFC tap and returns the raw Fiserv response
    /// as a dictionary (forwarded as-is to the Payabli backend via PATCH /update).
    func charge(amount: Decimal, merchantTransactionId: String?) async throws -> [String: Any] {
        guard let reader else { throw PayabliTTPError.notInitialized }

        let roundedAmount = amount.rounded(2, .bankers)

        let transactionDetails = Models.TransactionDetailsRequest(
            merchantTransactionId: merchantTransactionId,
            captureFlag: true,
            createToken: false
        )

        let response = try await reader.charges(
            amount: roundedAmount,
            transactionType: .sale,
            transactionDetailsRequest: transactionDetails
        )

        return try encodeToDictionary(response)
    }

    // MARK: - Internal

    private static func mapEnvironment(_ value: String) -> FiservTTPEnvironment {
        switch value.uppercased() {
        case "CERT", "QA":
            return .QA
        case "SANDBOX":
            return .Sandbox
        case "PROD", "PRODUCTION":
            return .Production
        default:
            return .QA
        }
    }

    /// Converts the Fiserv response into [String: Any] so we can forward it
    /// as raw JSON to the Payabli backend without mapping every Fiserv field.
    private func encodeToDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PayabliTTPError.fiservError("Failed to serialize Fiserv response")
        }
        return dict
    }
}

// MARK: - Decimal rounding (matching POC behavior)

private extension Decimal {
    func rounded(_ scale: Int, _ roundingMode: NSDecimalNumber.RoundingMode) -> Decimal {
        var result = Decimal()
        var localCopy = self
        NSDecimalRound(&result, &localCopy, scale, roundingMode)
        return result
    }
}
