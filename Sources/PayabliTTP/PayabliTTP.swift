import Foundation
import Combine

/// Main entry point for the PayabliTTP SDK.
///
/// Usage:
/// ```swift
/// let ttp = PayabliTTP(apiKey: "pk_...", entry: "myapp", deviceId: "dev_abc123")
/// try await ttp.initialize()
/// let result = try await ttp.charge(amount: 9.99, type: .sale)
/// ```
///
/// Observe events:
/// ```swift
/// for await event in ttp.events {
///     switch event { ... }
/// }
/// ```
@MainActor
public final class PayabliTTP: ObservableObject {

    // MARK: - Public state

    @Published public private(set) var sessionState: SessionState = .idle
    @Published public private(set) var isReady: Bool = false

    /// Stream of domain events for observability.
    public var events: AsyncStream<PayabliTTPEvent> {
        eventStream.stream
    }

    /// Any failed backend updates pending retry.
    public var pendingUpdates: [PendingUpdate] {
        pendingQueue.all()
    }

    // MARK: - Internal components (wired via Hexagonal Architecture)

    private let configuration: PayabliTTPConfiguration
    private let eventStream: EventStream

    // Ports (protocols)
    private let storage: SecureStorage
    private let attester: DeviceAttesting
    private let http: Networking
    private let cardReader: CardReading

    // Domain services
    private let attestationService: AttestationService
    private let transactionService: TransactionService
    private let sessionManager: SessionManager
    private let paymentOrchestrator: PaymentOrchestrator
    private let pendingQueue: PendingUpdateQueue

    // MARK: - Initialization

    public init(
        apiKey: String,
        entry: String,
        deviceId: String,
        environment: PayabliTTPEnvironment = .production,
        logLevel: LogLevel = .none
    ) {
        let config = PayabliTTPConfiguration(
            apiKey: apiKey,
            entry: entry,
            deviceId: deviceId,
            environment: environment,
            logLevel: logLevel
        )
        self.configuration = config
        Log.level = logLevel

        // Infrastructure
        let storage = KeychainStore()
        let http = HTTPClient(configuration: config)
        let attester = DeviceAttestManager(storage: storage)
        let cardReader = FiservCardReader()
        let eventStream = EventStream()
        let pendingQueue = PendingUpdateQueue()

        // Services
        let attestationService = AttestationService(http: http)
        let transactionService = TransactionService(http: http)

        // Orchestrators
        let sessionManager = SessionManager(
            attester: attester,
            attestationService: attestationService,
            transactionService: transactionService,
            cardReader: cardReader,
            deviceId: config.deviceId,
            events: eventStream
        )

        let paymentOrchestrator = PaymentOrchestrator(
            transactionService: transactionService,
            cardReader: cardReader,
            deviceId: config.deviceId,
            pendingQueue: pendingQueue,
            events: eventStream,
            entry: config.entry
        )

        // Store references
        self.storage = storage
        self.http = http
        self.attester = attester
        self.cardReader = cardReader
        self.eventStream = eventStream
        self.pendingQueue = pendingQueue
        self.attestationService = attestationService
        self.transactionService = transactionService
        self.sessionManager = sessionManager
        self.paymentOrchestrator = paymentOrchestrator
    }

    // MARK: - Public API

    /// Initialize the SDK: attest device, fetch config, set up NFC reader.
    /// Must be called once before charge().
    public func initialize() async throws {
        Log.session.info("Starting SDK initialization")

        do {
            try await sessionManager.initialize()
            sessionState = sessionManager.state
            isReady = sessionManager.isReady

            await paymentOrchestrator.retryPendingUpdates()

            Log.session.info("SDK initialization complete")
        } catch {
            sessionState = .error(error.localizedDescription)
            isReady = false
            Log.session.error("SDK initialization failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Execute a Tap to Pay transaction.
    /// Automatically calls reinitializeIfNeeded() if the session expired.
    public func charge(
        amount: Decimal,
        type: PaymentType = .sale,
        order: OrderDetails? = nil,
        customer: CustomerData? = nil,
        invoice: InvoiceData? = nil,
        serviceFee: Decimal? = nil
    ) async throws -> TransactionResult {
        guard case .sale = type else {
            throw PayabliTTPError.invalidState("Only .sale is supported in this version. Auth/refund coming in Phase 2.")
        }

        Log.payment.info("Starting charge: \(amount)")

        try await reinitializeIfNeeded()

        guard isReady else {
            throw PayabliTTPError.notInitialized
        }

        let result = try await paymentOrchestrator.chargeSale(
            amount: amount,
            order: order,
            customer: customer,
            invoice: invoice,
            serviceFee: serviceFee
        )

        Log.payment.info("Charge completed: \(result.transactionId) [\(result.syncStatus)]")
        return result
    }

    /// Re-establish the NFC session if it has expired.
    /// Called automatically by charge(), but can be called proactively
    /// by partners to optimize UX (e.g., before showing the payment screen).
    public func reinitializeIfNeeded() async throws {
        do {
            try await sessionManager.reinitializeIfNeeded()
            sessionState = sessionManager.state
            isReady = sessionManager.isReady
        } catch {
            sessionState = .error(error.localizedDescription)
            isReady = false
            throw error
        }
    }
}
