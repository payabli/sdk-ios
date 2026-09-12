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
package final class FiservCardReader: TapToPayProvider, @unchecked Sendable {
    package static var providerId: String {
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

    /// Set only by a test, so the linked, unlinked and platform-error answers are
    /// reachable without reader hardware. `prepareReader()` never assigns it, so
    /// the shipped path always asks the reader it built.
    private var injectedLinkStateSource: AccountLinking?

    /// Whatever `prepareReader()` last built, which in a shipped build is the vendored reader and
    /// in a test is the injected one. Held apart from `reader` because that stays the vendored
    /// type the charge path needs.
    private var preparedReader: ReaderSetup?

    /// Builds the reader `prepareReader()` drives. Set only by a test; `nil` in every shipped
    /// build, where the vendored reader is constructed instead.
    private var injectedReaderFactory: ((Credentials) throws -> ReaderSetup)?

    /// Whatever the terms surface asks. Read under the lock by its caller.
    private var linkStateSource: AccountLinking? {
        if let injectedLinkStateSource {
            return injectedLinkStateSource
        }
        return preparedReader
    }

    /// Injects what the terms surface reads and presents. Tests only.
    func setLinkStateSource(_ source: AccountLinking?) {
        lock.lock()
        injectedLinkStateSource = source
        lock.unlock()
    }

    /// Injects the reader `prepareReader()` drives. Tests only.
    func setReaderFactory(_ make: ((Credentials) throws -> ReaderSetup)?) {
        lock.lock()
        injectedReaderFactory = make
        lock.unlock()
    }

    package init() {}

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
    package func configure(credentials raw: [String: String]) throws {
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
    package func checkEligibility() async -> Result<Void, PayabliTTPError> {
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

    package func prepareReader() async throws {
        #if canImport(PayabliCardReaderCore)
            let creds = try requireCredentials()
            let injected = lock.withLock { injectedReaderFactory }
            let newReader: ReaderSetup = try injected.map { try $0(creds) }
                ?? buildReader(credentials: creds)

            // Credentials now live inside `newReader`, so this copy is dropped (NFR-5D).
            lock.withLock {
                preparedReader = newReader
                credentials = nil
            }

            logger.info("[fiserv.prepare] → requesting session")
            do {
                try await newReader.requestSessionToken()

                let linked = try await newReader.isAccountLinked()
                if !linked {
                    try await newReader.linkAccount()
                }

                do {
                    try await newReader.initializeSession()
                } catch {
                    // Opening the session is the only step the platform refuses over terms, so it is
                    // the only failure read that way. The steps before it leave the merchant unlinked
                    // whenever they fail at all — a dropped connection while presenting the sheet is
                    // still an unlinked merchant — and calling those unaccepted terms would hide an
                    // operational failure behind a state the host cannot resolve by asking again.
                    guard try await isNotLinked(newReader) else { throw error }
                    logger.info("[fiserv.prepare] ← terms not accepted; reader kept")
                    throw PayabliTTPError.termsNotAccepted
                }

                logger.info("[fiserv.prepare] ← reader ready (linked=\(linked))")
            } catch PayabliTTPError.termsNotAccepted {
                // The one setup failure that leaves the reader in use, and it has to: the reader holds
                // the session token presenting the sheet needs, and it is what answers whether the
                // merchant has accepted afterwards. Clearing it would leave a host holding a failure it
                // has no way to act on.
                throw PayabliTTPError.termsNotAccepted
            } catch {
                clearAllState()
                throw Self.mapError(error) { .readerSetupFailed(reason: $0) }
            }
        #else
            throw PayabliTTPError.readerSetupFailed(reason: "Tap to Pay is iOS-only")
        #endif
    }

    package func areTermsAccepted() async throws -> Bool {
        #if canImport(PayabliCardReaderCore)
            // Scoped rather than `lock()`/`unlock()`, which the neighbours use and
            // which is an error under the Swift 6 language mode from an async context.
            let source = lock.withLock { linkStateSource }
            guard let source else {
                throw PayabliTTPError.readerSetupFailed(reason: "Reader not prepared")
            }

            do {
                return try await source.isAccountLinked()
            } catch {
                throw Self.mapError(error) { .readerSetupFailed(reason: $0) }
            }
        #else
            throw PayabliTTPError.readerSetupFailed(reason: "Tap to Pay is iOS-only")
        #endif
    }

    #if canImport(PayabliCardReaderCore)
        /// Whether setup failed because the merchant has not accepted, asked of the reader rather than
        /// read off the error.
        ///
        /// The platform refuses this with a typed case, and the vendored reader rewraps it as its own
        /// error carrying only the platform's prose. Matching that text would bind this decision to
        /// wording nobody in this repository controls, where the reader answers the question directly
        /// and authoritatively.
        ///
        /// A reader that cannot answer at all is not the terms case: `false` here sends the original
        /// failure on unchanged.
        private func isNotLinked(_ reader: AccountLinking) async throws -> Bool {
            (try? await reader.isAccountLinked()) == false
        }
    #endif

    package func presentTerms() async throws {
        #if canImport(PayabliCardReaderCore)
            // Same reader the answer comes from, and the same reason for the scoped read as above.
            let source = lock.withLock { linkStateSource }
            guard let source else {
                throw PayabliTTPError.readerSetupFailed(reason: "Reader not prepared")
            }

            do {
                try await source.linkAccount()
            } catch {
                throw Self.mapError(error) { .readerSetupFailed(reason: $0) }
            }
        #else
            throw PayabliTTPError.readerSetupFailed(reason: "Tap to Pay is iOS-only")
        #endif
    }

    package func startReading(_ request: CardReadRequest) async throws -> CardReadResult {
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
            // The atomic card-reader API has no slot for customer data; it ships
            // at /initiate only. A single-argument message renders `.public`, so
            // the line above carries the invoice number and nothing naming the
            // customer.

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
            // `CommerceHubResponse` carries `paymentTokens.tokenData` and the
            // card's expiry, so the log gets the shape of the response.
            logger.info("[fiserv.charges] ← OK (\(elapsedMs)ms) bytes=\(responseJSON.count) cardNetwork=\(cardNetwork ?? "<nil>")")
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

    package func cancelReading() async {
        logger.info("[fiserv.cancel] clearing reader state")
        clearAllState()
    }

    package func cleanUp() async {
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
        preparedReader = nil
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
