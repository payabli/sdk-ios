import Foundation
import PayabliSDKTapToPay

/// Mock `TapToPayProvider` for unit tests that exercise the TTP session and
/// charge flows without requiring a physical NFC reader.
public final class MockTapToPayProvider: TapToPayProvider, @unchecked Sendable {
    public static var providerId: String { "mock" }

    private let lock = NSLock()

    private var _eligibility: Result<Void, PayabliTTPError> = .success(())
    public var eligibility: Result<Void, PayabliTTPError> {
        get { lock.withLock { _eligibility } }
        set { lock.withLock { _eligibility = newValue } }
    }

    private var _prepareReaderResult: Result<Void, Error> = .success(())
    public var prepareReaderResult: Result<Void, Error> {
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
    public var readingResult: Result<CardReadResult, Error> {
        get { lock.withLock { _readingResult } }
        set { lock.withLock { _readingResult = newValue } }
    }

    private var _prepareReaderCalls = 0
    public var prepareReaderCalls: Int {
        lock.withLock { _prepareReaderCalls }
    }

    private var _configureCalls = 0
    public var configureCalls: Int {
        lock.withLock { _configureCalls }
    }

    private var _startReadingCalls = 0
    public var startReadingCalls: Int {
        lock.withLock { _startReadingCalls }
    }

    private var _cancelCalls = 0
    public var cancelCalls: Int {
        lock.withLock { _cancelCalls }
    }

    private var _cleanUpCalls = 0
    public var cleanUpCalls: Int {
        lock.withLock { _cleanUpCalls }
    }

    private var _lastConfiguredCredentials: [String: String]?
    public var lastConfiguredCredentials: [String: String]? {
        get { lock.withLock { _lastConfiguredCredentials } }
        set { lock.withLock { _lastConfiguredCredentials = newValue } }
    }

    private var _configureResult: Result<Void, Error> = .success(())
    public var configureResult: Result<Void, Error> {
        get { lock.withLock { _configureResult } }
        set { lock.withLock { _configureResult = newValue } }
    }

    public init() {}

    public func checkEligibility() async -> Result<Void, PayabliTTPError> {
        lock.withLock { _eligibility }
    }

    public func configure(credentials: [String: String]) throws {
        let result: Result<Void, Error> = lock.withLock {
            _configureCalls += 1
            _lastConfiguredCredentials = credentials
            return _configureResult
        }
        if case .failure(let err) = result { throw err }
    }

    public func prepareReader() async throws {
        let result: Result<Void, Error> = lock.withLock {
            _prepareReaderCalls += 1
            return _prepareReaderResult
        }
        if case .failure(let err) = result { throw err }
    }

    public func startReading(_ request: CardReadRequest) async throws -> CardReadResult {
        let result: Result<CardReadResult, Error> = lock.withLock {
            _startReadingCalls += 1
            return _readingResult
        }
        switch result {
        case .success(let value): return value
        case .failure(let err): throw err
        }
    }

    public func cancelReading() async {
        lock.withLock { _cancelCalls += 1 }
    }

    public func cleanUp() async {
        lock.withLock { _cleanUpCalls += 1 }
    }
}
