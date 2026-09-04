import Foundation
import PayabliSDKTapToPay

/// Mock `TapToPayProvider` for unit tests that exercise the TTP session and
/// charge flows without requiring a physical NFC reader.
package final class MockTapToPayProvider: TapToPayProvider, @unchecked Sendable {
    package static var providerId: String {
        "mock"
    }

    private let lock = NSLock()

    private var _eligibility: Result<Void, PayabliTTPError> = .success(())
    package var eligibility: Result<Void, PayabliTTPError> {
        get { lock.withLock { _eligibility } }
        set { lock.withLock { _eligibility = newValue } }
    }

    private var _prepareReaderResult: Result<Void, Error> = .success(())
    package var prepareReaderResult: Result<Void, Error> {
        get { lock.withLock { _prepareReaderResult } }
        set { lock.withLock { _prepareReaderResult = newValue } }
    }

    private var _readingResult: Result<CardReadResult, Error> = .success(
        CardReadResult(
            provider: "mock",
            encryptedPayload: Data("encrypted".utf8),
            cardNetwork: "Visa",
            providerMetadata: ["last4": "1111"]
        )
    )
    package var readingResult: Result<CardReadResult, Error> {
        get { lock.withLock { _readingResult } }
        set { lock.withLock { _readingResult = newValue } }
    }

    private var _prepareReaderCalls = 0
    package var prepareReaderCalls: Int {
        lock.withLock { _prepareReaderCalls }
    }

    private var _configureCalls = 0
    package var configureCalls: Int {
        lock.withLock { _configureCalls }
    }

    private var _startReadingCalls = 0
    package var startReadingCalls: Int {
        lock.withLock { _startReadingCalls }
    }

    private var _cancelCalls = 0
    package var cancelCalls: Int {
        lock.withLock { _cancelCalls }
    }

    private var _cleanUpCalls = 0
    package var cleanUpCalls: Int {
        lock.withLock { _cleanUpCalls }
    }

    private var _lastConfiguredCredentials: [String: String]?
    package var lastConfiguredCredentials: [String: String]? {
        get { lock.withLock { _lastConfiguredCredentials } }
        set { lock.withLock { _lastConfiguredCredentials = newValue } }
    }

    private var _configureResult: Result<Void, Error> = .success(())
    package var configureResult: Result<Void, Error> {
        get { lock.withLock { _configureResult } }
        set { lock.withLock { _configureResult = newValue } }
    }

    package init() {}

    package func checkEligibility() async -> Result<Void, PayabliTTPError> {
        lock.withLock { _eligibility }
    }

    package func configure(credentials: [String: String]) throws {
        let result: Result<Void, Error> = lock.withLock {
            _configureCalls += 1
            _lastConfiguredCredentials = credentials
            return _configureResult
        }
        if case let .failure(err) = result {
            throw err
        }
    }

    package func prepareReader() async throws {
        let result: Result<Void, Error> = lock.withLock {
            _prepareReaderCalls += 1
            return _prepareReaderResult
        }
        if case let .failure(err) = result {
            throw err
        }
    }

    package func startReading(_ request: CardReadRequest) async throws -> CardReadResult {
        let result: Result<CardReadResult, Error> = lock.withLock {
            _startReadingCalls += 1
            return _readingResult
        }
        switch result {
        case let .success(value): return value
        case let .failure(err): throw err
        }
    }

    package func cancelReading() async {
        lock.withLock { _cancelCalls += 1 }
    }

    package func cleanUp() async {
        lock.withLock { _cleanUpCalls += 1 }
    }
}
