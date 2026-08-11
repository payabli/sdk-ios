import Foundation
import PayabliSDKCore
#if canImport(PayabliCardReaderCore)
    import PayabliCardReaderCore
    import ProximityReader
#endif

/// Card-reader adapter for `TapToPayProvider` (PRD FR-11B), backed by the
/// vendored `PayabliCardReaderCore` module.
///
/// `charges(amount:)` is atomic (NFC read + charge in one call), so
/// `startReading` returns the full processor response as
/// `providerResponseJSON` for the facade to forward verbatim.
///
/// Credentials come from `/config` (FR-11B.3), live in RAM only (NFR-5D),
/// and are dropped from `self` as soon as `buildReader` hands them to the
/// card-reader SDK. Retries require a fresh `/config` fetch.
///
/// Error mapping: see `FiservCardReader+Errors.swift`.
public final class FiservCardReader: TapToPayProvider, @unchecked Sendable {
    public static var providerId: String {
        "fiserv"
    }

    /// `/config` `credentials` block — maps 1:1 to `FiservTTPConfig`.
    struct Credentials: Sendable {
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

        init(
            secretKey: String,
            apiKey: String,
            environment: String,
            currencyCode: String,
            merchantId: String,
            appleTtpMerchantId: String,
            merchantName: String,
            merchantCategoryCode: String,
            terminalId: String,
            terminalProfileId: String
        ) {
            self.secretKey = secretKey
            self.apiKey = apiKey
            self.environment = environment
            self.currencyCode = currencyCode
            self.merchantId = merchantId
            self.appleTtpMerchantId = appleTtpMerchantId
            self.merchantName = merchantName
            self.merchantCategoryCode = merchantCategoryCode
            self.terminalId = terminalId
            self.terminalProfileId = terminalProfileId
        }
    }

    private let lock = NSLock()
    private var credentials: Credentials?
    private let logger = PayabliLogger(category: .taptopay)

    #if canImport(PayabliCardReaderCore)
        private var reader: FiservTTPCardReader?
    #endif

    public init() {}

    /// Injects `Credentials` directly. Facade path uses `configure(credentials:)`.
    func setCredentials(_ credentials: Credentials) {
        lock.lock()
        self.credentials = credentials
        lock.unlock()
    }

    // MARK: - TapToPayProvider

    /// Keys that must be present and non-empty in the `/config` dict.
    static let requiredCredentialKeys: [String] = [
        "secretKey", "apiKey", "merchantId", "terminalId"
    ]

    /// Keys that fall back to safe defaults; `configure` logs a warning for
    /// each one missing.
    static let optionalCredentialKeys: [String] = [
        "environment", "currencyCode", "appleTtpMerchantId",
        "merchantName", "merchantCategoryCode", "terminalProfileId"
    ]

    /// Validates the `/config` `providerCredentials` dict and stores it as
    /// `Credentials`. Throws on any missing required key.
    public func configure(credentials raw: [String: String]) throws {
        let missing = Self.requiredCredentialKeys.filter { raw[$0]?.isEmpty != false }
        guard missing.isEmpty else {
            throw PayabliTTPError.readerSetupFailed(
                reason: "Provider credentials missing required field(s): \(missing.joined(separator: ", "))"
            )
        }

        let missingOptional = Self.optionalCredentialKeys.filter { raw[$0]?.isEmpty != false }
        if !missingOptional.isEmpty {
            logger.warning(
                "[fiserv.configure] optional credentials missing, using defaults: \(missingOptional.joined(separator: ", "))"
            )
        }

        setCredentials(
            Credentials(
                secretKey: raw["secretKey"] ?? "",
                apiKey: raw["apiKey"] ?? "",
                environment: raw["environment"] ?? "sandbox",
                currencyCode: raw["currencyCode"] ?? "USD",
                merchantId: raw["merchantId"] ?? "",
                appleTtpMerchantId: raw["appleTtpMerchantId"] ?? "",
                merchantName: raw["merchantName"] ?? "",
                merchantCategoryCode: raw["merchantCategoryCode"] ?? "",
                terminalId: raw["terminalId"] ?? "",
                terminalProfileId: raw["terminalProfileId"] ?? ""
            )
        )
    }

    /// Platform + `PaymentCardReader` hardware check. Runs before `/config`
    /// is fetched, so must not require credentials.
    public func checkEligibility() async -> Result<Void, PayabliTTPError> {
        #if canImport(PayabliCardReaderCore)
            if #available(iOS 16.7, *) {
                guard PaymentCardReader.isSupported else {
                    return .failure(.readerSetupFailed(
                        reason: "Tap to Pay hardware not supported on this device"
                    ))
                }
                return .success(())
            }
            return .failure(.readerSetupFailed(reason: "Tap to Pay requires iOS 16.7+"))
        #else
            return .failure(.readerSetupFailed(reason: "Tap to Pay is iOS-only"))
        #endif
    }

    public func prepareReader() async throws {
        #if canImport(PayabliCardReaderCore)
            let creds = try requireCredentials()
            let newReader = try buildReader(credentials: creds)

            // Drop our copy; credentials now live inside `newReader` (NFR-5D).
            lock.lock()
            credentials = nil
            lock.unlock()

            logger.info("[fiserv.prepare] → requesting session")
            do {
                try await newReader.requestSessionToken()

                let linked = try await newReader.isAccountLinked()
                if !linked {
                    try await newReader.linkAccount()
                }

                try await newReader.initializeSession()
                logger.info("[fiserv.prepare] ← reader ready (linked=\(linked))")
            } catch {
                clearAllState()
                throw Self.mapError(error) { .readerSetupFailed(reason: $0) }
            }
        #else
            throw PayabliTTPError.readerSetupFailed(reason: "Tap to Pay is iOS-only")
        #endif
    }

    public func startReading(_ request: CardReadRequest) async throws -> CardReadResult {
        #if canImport(PayabliCardReaderCore)
            lock.lock()
            let activeReader = reader
            lock.unlock()
            guard let reader = activeReader else {
                throw PayabliTTPError.readerSetupFailed(reason: "Reader not prepared")
            }

            let amount = request.amount.rounded(2, .bankers)
            let details = Models.TransactionDetailsRequest(
                merchantTransactionId: request.merchantTransactionId,
                merchantOrderId: request.merchantOrderId ?? request.merchantTransactionId,
                merchantInvoiceNumber: request.merchantInvoiceNumber,
                captureFlag: true,
                createToken: false
            )

            logger.info(
                "[fiserv.charges] → amount=\(amount) " +
                    "currency=\(credentials?.currencyCode ?? "?") " +
                    "merchantTxId=\(request.merchantTransactionId) " +
                    "merchantOrderId=\(request.merchantOrderId ?? "<nil>") " +
                    "invoice=\(request.merchantInvoiceNumber ?? "<nil>")"
            )
            logger.info(
                "[fiserv.charges] customer={firstName=\(request.customer.firstName ?? "<nil>") " +
                    "lastName=\(request.customer.lastName ?? "<nil>") " +
                    "customerNumber=\(request.customer.customerNumber ?? "<nil>")} " +
                    "invoice={invoiceNumber=\(request.invoice.invoiceNumber ?? "<nil>")}"
            )
            // The atomic card-reader API has no slot for customer data; it
            // ships only at /initiate and in the logs above.

            let started = Date()
            let response: Models.CommerceHubResponse
            do {
                response = try await reader.charges(
                    amount: amount,
                    transactionType: .sale,
                    transactionDetailsRequest: details
                )
            } catch {
                throw Self.mapError(error) { .nfcFailed(reason: $0) }
            }

            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            let responseJSON = try Self.encode(response)
            let cardNetwork = Self.extractCardNetwork(from: responseJSON)
            logger.info("[fiserv.charges] ← OK (\(elapsedMs)ms) bytes=\(responseJSON.count) cardNetwork=\(cardNetwork ?? "<nil>")")
            if let pretty = Self.prettyPrintJSON(responseJSON) {
                logger.info("[fiserv.charges] responseBody:\n\(pretty)")
            }
            return CardReadResult(
                provider: Self.providerId,
                encryptedPayload: Data(),
                cardNetwork: cardNetwork,
                providerMetadata: [:],
                providerResponseJSON: responseJSON
            )
        #else
            throw PayabliTTPError.nfcFailed(reason: "Tap to Pay is iOS-only")
        #endif
    }

    public func cancelReading() async {
        logger.info("[fiserv.cancel] clearing reader state")
        clearAllState()
    }

    public func cleanUp() async {
        logger.info("[fiserv.cleanup] clearing reader state")
        clearAllState()
    }

    // MARK: - Private

    /// Releases the reader and clears `self.credentials`. After this the
    /// adapter requires a full `configure()` + `prepareReader()` cycle.
    /// Synchronous so the lock is safe from `async` callers.
    private func clearAllState() {
        lock.lock()
        #if canImport(PayabliCardReaderCore)
            reader?.finalize()
            reader = nil
        #endif
        credentials = nil
        lock.unlock()
    }

    #if canImport(PayabliCardReaderCore)
        private func requireCredentials() throws -> Credentials {
            lock.lock()
            defer { lock.unlock() }
            guard let creds = credentials else {
                throw PayabliTTPError.readerSetupFailed(reason: "Missing provider credentials")
            }
            return creds
        }

        /// Builds a fresh `FiservTTPCardReader` (vendored from PayabliCardReaderCore).
        /// Tears down the previous instance first — Apple's `PaymentCardReader`
        /// allows only one per process.
        private func buildReader(credentials creds: Credentials) throws -> FiservTTPCardReader {
            lock.lock()
            reader?.finalize()
            reader = nil
            lock.unlock()

            let config = FiservTTPConfig(
                secretKey: creds.secretKey,
                apiKey: creds.apiKey,
                environment: creds.environment.lowercased() == "production" ? .Production : .Sandbox,
                currencyCode: creds.currencyCode,
                merchantId: creds.merchantId,
                appleTtpMerchantId: creds.appleTtpMerchantId,
                merchantName: creds.merchantName,
                merchantCategoryCode: creds.merchantCategoryCode,
                terminalId: creds.terminalId,
                terminalProfileId: creds.terminalProfileId
            )

            let newReader = FiservTTPCardReader(configuration: config)

            lock.lock()
            reader = newReader
            lock.unlock()

            return newReader
        }

        private static func encode(_ value: some Encodable) throws -> Data {
            do {
                return try JSONEncoder().encode(value)
            } catch {
                throw PayabliTTPError.nfcFailed(
                    reason: "Failed to encode provider response: \(error.localizedDescription)"
                )
            }
        }

        /// Re-encodes `json` with `.prettyPrinted` + `.sortedKeys` for log output.
        /// Returns `nil` if `json` isn't valid JSON.
        private static func prettyPrintJSON(_ json: Data) -> String? {
            guard
                let obj = try? JSONSerialization.jsonObject(with: json),
                let pretty = try? JSONSerialization.data(
                    withJSONObject: obj,
                    options: [.prettyPrinted, .sortedKeys]
                )
            else { return nil }
            return String(data: pretty, encoding: .utf8)
        }

        /// Pulls `card.brand` out of the CommerceHub response for
        /// `CardReadResult.cardNetwork`. Tolerates minor schema drift.
        private static func extractCardNetwork(from json: Data) -> String? {
            guard
                let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
            else { return nil }
            if let pm = (obj["source"] as? [String: Any]) ?? (obj["paymentSources"] as? [String: Any]) {
                if let brand = pm["brand"] as? String {
                    return brand
                }
                if let card = pm["card"] as? [String: Any], let brand = card["brand"] as? String {
                    return brand
                }
            }
            return nil
        }
    #endif
}

// MARK: - Decimal rounding

private extension Decimal {
    func rounded(_ scale: Int, _ roundingMode: NSDecimalNumber.RoundingMode) -> Decimal {
        var result = Decimal()
        var localCopy = self
        NSDecimalRound(&result, &localCopy, scale, roundingMode)
        return result
    }
}
