import Foundation
import PayabliSDKCore
#if canImport(FiservTTP)
import FiservTTP
import ProximityReader
import Combine
#endif

/// Fiserv adapter for `TapToPayProvider` (PRD FR-11B).
///
/// Wraps the Fiserv `FiservTTP` SDK (≥ 1.0.7) to accept contactless NFC
/// payments on iPhone via Apple's ProximityReader. `charges(amount:)` is
/// atomic — NFC tap and charge happen in a single SDK call — so this adapter
/// returns the full processor response as `CardReadResult.providerResponseJSON`
/// so the facade can forward it verbatim under the backend's `fiservResponse`
/// key.
///
/// Runtime-only credentials: every Fiserv field (`secretKey`, `apiKey`,
/// `environment`, `currencyCode`, `merchantId`, `appleTtpMerchantId`,
/// `merchantName`, `merchantCategoryCode`, `terminalId`, `terminalProfileId`)
/// is delivered via the Payabli `/config` endpoint (FR-11B.3) and lives only
/// in RAM (NFR-5D). This class never persists them.
public final class FiservCardReader: TapToPayProvider, @unchecked Sendable {

    public static var providerId: String { "fiserv" }

    /// Full set of Fiserv credentials required by `FiservTTPConfig`.
    /// Matches the `credentials` block returned by `/api/v2/device/taptopay/config/{entry}`.
    public struct Credentials: Sendable {
        public let secretKey: String
        public let apiKey: String
        /// `"production"` → `.Production`, anything else → `.Sandbox`.
        public let environment: String
        public let currencyCode: String
        public let merchantId: String
        public let appleTtpMerchantId: String
        public let merchantName: String
        public let merchantCategoryCode: String
        public let terminalId: String
        public let terminalProfileId: String

        public init(
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

    #if canImport(FiservTTP)
    private var reader: FiservTTPCardReader?
    private var sessionReadyCancellable: AnyCancellable?
    private var _isSessionActive: Bool = false
    private var isSessionActive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isSessionActive }
        set { lock.lock(); defer { lock.unlock() }; _isSessionActive = newValue }
    }
    #endif

    public init() {}

    /// Inject credentials directly (typed). Useful for tests and hosts that
    /// build the `Credentials` struct themselves; the facade path goes through
    /// `configure(credentials:)`.
    public func setCredentials(_ credentials: Credentials) {
        lock.lock()
        self.credentials = credentials
        lock.unlock()
    }

    /// Convenience for the 10 raw fields that come from the `/config` envelope.
    public func setCredentials(
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
        setCredentials(
            Credentials(
                secretKey: secretKey,
                apiKey: apiKey,
                environment: environment,
                currencyCode: currencyCode,
                merchantId: merchantId,
                appleTtpMerchantId: appleTtpMerchantId,
                merchantName: merchantName,
                merchantCategoryCode: merchantCategoryCode,
                terminalId: terminalId,
                terminalProfileId: terminalProfileId
            )
        )
    }

    // MARK: - TapToPayProvider

    /// Keys expected in the `/config` `providerCredentials` block for Fiserv.
    /// Exposed `internal` so tests can assert against the contract.
    static let requiredCredentialKeys: [String] = [
        "secretKey", "apiKey", "merchantId", "terminalId"
    ]

    /// Optional keys — if missing, the adapter falls back to safe defaults
    /// (e.g. environment → `"sandbox"`) but logs a descriptive message.
    static let optionalCredentialKeys: [String] = [
        "environment", "currencyCode", "appleTtpMerchantId",
        "merchantName", "merchantCategoryCode", "terminalProfileId"
    ]

    /// Consumes the opaque `providerCredentials` dict from `/config` and
    /// produces a typed `Credentials` struct. Fails loudly when a required
    /// field is missing so `initialize()` surfaces a descriptive error before
    /// any NFC UI is attempted.
    public func configure(credentials raw: [String: String]) throws {
        let missing = Self.requiredCredentialKeys.filter { raw[$0]?.isEmpty != false }
        guard missing.isEmpty else {
            throw PayabliTTPError.readerSetupFailed(
                reason: "Fiserv credentials missing required field(s): \(missing.joined(separator: ", "))"
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

    /// Validates platform + Apple ProximityReader support. Intentionally does
    /// NOT require credentials: eligibility runs before `/config` is fetched.
    public func checkEligibility() async -> Result<Void, PayabliTTPError> {
        #if canImport(FiservTTP)
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
        #if canImport(FiservTTP)
        let creds = try requireCredentials()
        let newReader = try buildReader(credentials: creds)

        do {
            try await newReader.requestSessionToken()

            let linked = try await newReader.isAccountLinked()
            if !linked {
                try await newReader.linkAccount()
            }

            try await newReader.initializeSession()
            isSessionActive = true
        } catch {
            throw Self.mapError(error, fallbackKind: .readerSetupFailed)
        }
        #else
        throw PayabliTTPError.readerSetupFailed(reason: "Tap to Pay is iOS-only")
        #endif
    }

    public func startReading(_ request: CardReadRequest) async throws -> CardReadResult {
        #if canImport(FiservTTP)
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

        logger.info("[fiserv.charges] → amount=\(amount) currency=\(credentials?.currencyCode ?? "?") merchantTxId=\(request.merchantTransactionId) merchantOrderId=\(request.merchantOrderId ?? "<nil>") invoice=\(request.merchantInvoiceNumber ?? "<nil>")")
        logger.info(
            "[fiserv.charges] customer={firstName=\(request.customer.firstName ?? "<nil>") " +
            "lastName=\(request.customer.lastName ?? "<nil>") " +
            "customerNumber=\(request.customer.customerNumber ?? "<nil>")} " +
            "order={orderId=\(request.order.orderId ?? "<nil>") " +
            "description=\(request.order.orderDescription ?? "<nil>") " +
            "invoiceNumber=\(request.order.invoiceNumber ?? "<nil>")}"
        )
        // NOTE: Fiserv's `charges(amount:)` atomic API does not accept a
        // billing address / cardholder name. The customer data is still
        // persisted at /initiate (step 1) and echoed in logs so that any
        // "John Doe"-style sandbox cardholder name in the CommerceHub
        // response can be traced back to the processor, not the SDK.

        let started = Date()
        let response: Models.CommerceHubResponse
        do {
            response = try await reader.charges(
                amount: amount,
                transactionType: .sale,
                transactionDetailsRequest: details
            )
        } catch {
            throw Self.mapError(error, fallbackKind: .nfcFailed)
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
        tearDownReader(clearingCredentials: false)
    }

    public func cleanUp() async {
        tearDownReader(clearingCredentials: true)
    }

    // MARK: - Private

    /// Releases the Fiserv reader and, optionally, the cached credentials.
    /// Kept synchronous so the lock can be used safely from `async` callers.
    private func tearDownReader(clearingCredentials: Bool) {
        lock.lock()
        #if canImport(FiservTTP)
        sessionReadyCancellable?.cancel()
        sessionReadyCancellable = nil
        reader?.finalize()
        reader = nil
        _isSessionActive = false
        #endif
        if clearingCredentials {
            credentials = nil
        }
        lock.unlock()
    }

    #if canImport(FiservTTP)
    private func requireCredentials() throws -> Credentials {
        lock.lock(); defer { lock.unlock() }
        guard let creds = credentials else {
            throw PayabliTTPError.readerSetupFailed(reason: "Missing Fiserv credentials")
        }
        return creds
    }

    /// Builds a fresh `FiservTTPCardReader`, tearing down any previous instance
    /// first — Apple's `PaymentCardReader` allows only one active instance per
    /// process.
    private func buildReader(credentials creds: Credentials) throws -> FiservTTPCardReader {
        lock.lock()
        sessionReadyCancellable?.cancel()
        sessionReadyCancellable = nil
        reader?.finalize()
        reader = nil
        _isSessionActive = false
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

        let cancellable = newReader.sessionReadySubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                self?.isSessionActive = ready
            }

        lock.lock()
        reader = newReader
        sessionReadyCancellable = cancellable
        lock.unlock()

        return newReader
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw PayabliTTPError.nfcFailed(
                reason: "Failed to encode Fiserv response: \(error.localizedDescription)"
            )
        }
    }

    /// Best-effort `card.brand` extraction from the Fiserv response for
    /// surfacing on `CardReadResult.cardNetwork`.
    /// Returns the JSON data re-encoded with `.prettyPrinted` for log
    /// readability, or `nil` if `json` isn't valid JSON.
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

    private static func extractCardNetwork(from json: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        else { return nil }
        // CommerceHub shape — tolerate minor schema drift.
        if let pm = (obj["source"] as? [String: Any]) ?? (obj["paymentSources"] as? [String: Any]) {
            if let brand = pm["brand"] as? String { return brand }
            if let card = pm["card"] as? [String: Any], let brand = card["brand"] as? String {
                return brand
            }
        }
        return nil
    }

    /// Map Fiserv / ProximityReader errors to `PayabliTTPError`. Cancellations
    /// become `.nfcFailed(reason: "cancelled: ...")`, so callers can detect them
    /// by substring if they need user-cancel UX.
    private static func mapError(
        _ error: Error,
        fallbackKind: PayabliTTPErrorKind
    ) -> PayabliTTPError {
        if let pte = error as? PayabliTTPError { return pte }

        if (error as NSError).code == NSUserCancelledError {
            return .nfcFailed(reason: "cancelled: user dismissed Tap to Pay sheet")
        }

        if #available(iOS 16.4, *), error is PaymentCardReaderError {
            let desc = error.localizedDescription
            if desc.lowercased().contains("version") {
                return .readerSetupFailed(reason: "OS version not supported: \(desc)")
            }
        }

        let detail = extractFiservDetail(error)
        let desc = detail.isEmpty ? error.localizedDescription : detail
        switch fallbackKind {
        case .readerSetupFailed: return .readerSetupFailed(reason: desc)
        case .nfcFailed: return .nfcFailed(reason: desc)
        }
    }

    /// `FiservTTPCardReaderError` is a struct whose stored `localizedDescription`
    /// property shadows — but does NOT override — `Error.localizedDescription`,
    /// so `error.localizedDescription` produces a generic NSError message. Pull
    /// the real title + description via reflection (matches the old SDK).
    private static func extractFiservDetail(_ error: Error) -> String {
        let mirror = Mirror(reflecting: error)
        let title = mirror.children.first(where: { $0.label == "title" })?.value as? String
        let desc = mirror.children.first(where: { $0.label == "localizedDescription" })?.value as? String
        if let title, let desc { return "\(title): \(desc)" }
        if let desc { return desc }
        return ""
    }
    #endif
}

/// Private discriminator used to route `mapError` to the correct fallback
/// `PayabliTTPError` case (setup vs. NFC failure).
private enum PayabliTTPErrorKind {
    case readerSetupFailed
    case nfcFailed
}

// MARK: - Decimal rounding (matches old SDK behavior)

private extension Decimal {
    func rounded(_ scale: Int, _ roundingMode: NSDecimalNumber.RoundingMode) -> Decimal {
        var result = Decimal()
        var localCopy = self
        NSDecimalRound(&result, &localCopy, scale, roundingMode)
        return result
    }
}
