import Foundation
import PayabliSDKCore

/// Unified Pay In component for storing payment methods and running v2 MoneyIn
/// auth/capture flows.
///
/// The component can exchange card or bank account data for a stored payment method, or
/// send card, bank account, stored-method, cash, check, or cloud-device payment requests
/// to the v2 MoneyIn endpoints. It does not log, persist, or expose raw PAN,
/// CVV, bank account, or routing values after submission.
@MainActor
public final class PayabliPayIn: NSObject, ObservableObject, PayabliComponent {
    package nonisolated static let componentId = "payIn"
    package nonisolated static let sessionTier: PayabliSessionTier = .tier1Transactional
    package nonisolated static let requiredPermissions = [
        "tokenstorage:add",
        "moneyin:getpaid",
        "moneyin:authorize",
        "moneyin:capture",
        "moneyin:void"
    ]

    @Published public private(set) var isSubmitting: Bool = false

    /// What the last submission the flow published ended as.
    ///
    /// **``voidTransaction(_:)`` does not appear here.** One channel per caller: a reversal answers the
    /// caller that asked for it and leaves this alone, so a screen showing what a payment did does not
    /// start showing what was done to it afterwards. Read that member's return value instead, and do
    /// not wait on this for it.
    @Published public private(set) var lastResult: PayabliPayInResult?

    public var lastStoredPaymentMethod: PayabliPayInStoredPaymentMethod? {
        lastResult?.storedPaymentMethod
    }

    public private(set) var entryPoint: String
    public private(set) var environment: PayabliEnvironment
    /// Mints the key for an attempt that supplied none.
    ///
    /// Settable rather than an initialiser parameter: every initialiser here already carries seven, and
    /// a test only needs this pinned before it submits. Not public, so a host cannot supply one.
    var newIdempotencyKey: @Sendable () -> String = { UUID().uuidString }
    var newPaymentReference: @Sendable () -> String = { UUID().uuidString.lowercased() }
    /// Reads the clock a held key ages against. One that keeps counting while the device sleeps.
    var now: @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }

    @Published public private(set) var operation: PayabliPayInOperation
    @Published public private(set) var requestConfiguration: PayabliPayInRequestConfiguration?

    private(set) var session: PayabliSession?
    private let injectedTransport: (any PayabliTransport)?
    private var client: PayInPaymentFlowClient
    private var tokenStorageClient: PayInPaymentFlowTokenStorageClient
    private var activeSubmissionCount = 0
    private var heldKeys = HeldIdempotencyKeys()
    private let logger = PayabliLogger(category: .tokenization)
    /// Nil on a flow built on a bare transport without a telemetry client.
    private(set) var reports: PayInReports?

    /// Builds the flow on a session, which carries the credential and the transport that sends it.
    ///
    /// The entry point and the environment come from the session's configuration, so a flow and the
    /// session it runs on cannot disagree about which merchant or which host they are for.
    ///
    /// - Parameters:
    ///   - session: The session the flow sends on.
    ///   - operation: What a submission does.
    ///   - requestConfiguration: The request the flow starts with, if any.
    public init(
        session: PayabliSession,
        operation: PayabliPayInOperation = .storePaymentMethod,
        requestConfiguration: PayabliPayInRequestConfiguration? = nil
    ) {
        self.entryPoint = session.config.entryPoint
        self.environment = session.config.environment
        self.operation = operation
        self.requestConfiguration = requestConfiguration
        self.session = session
        injectedTransport = nil
        client = PayInPaymentFlowClient(transport: session.transport)
        tokenStorageClient = PayInPaymentFlowTokenStorageClient(transport: session.transport)
        reports = PayInReports(telemetry: session.telemetry)
        super.init()
    }

    /// A flow on a transport supplied whole, for tests that answer requests themselves.
    ///
    /// There is no token source here because there is nothing to authenticate: the transport given
    /// is the one used, and a fake one never reads a credential.
    ///
    /// - Parameter entryPoint: the paypoint's entry point, as the requests carry it.
    /// - Parameter environment: the environment the requests go to, whose base URL builds the routes.
    /// - Parameter transport: the transport that sends every request, used whole.
    /// - Parameter operation: what a rendered form submits, `.storePaymentMethod` when nothing is given.
    /// - Parameter requestConfiguration: the transaction configuration a rendered form's request is built from.
    /// - Parameter telemetry: where the flow reports its operations, nil to report nothing.
    init(
        entryPoint: String,
        environment: PayabliEnvironment,
        transport: any PayabliTransport,
        operation: PayabliPayInOperation = .storePaymentMethod,
        requestConfiguration: PayabliPayInRequestConfiguration? = nil,
        telemetry: TelemetryClient? = nil
    ) {
        self.entryPoint = entryPoint
        self.environment = environment
        self.operation = operation
        self.requestConfiguration = requestConfiguration
        session = nil
        injectedTransport = transport
        client = PayInPaymentFlowClient(transport: transport)
        tokenStorageClient = PayInPaymentFlowTokenStorageClient(transport: transport)
        reports = telemetry.map(PayInReports.init(telemetry:))
        super.init()
    }

    /// Points the flow at a configuration, which has to be the one the installed session runs on.
    ///
    /// The process has one session, so a different configuration, or none installed, is not applied:
    /// the flow keeps its entry point and environment, and every submission after it fails with
    /// `invalidConfiguration`.
    ///
    /// - Parameter config: the configuration to run on, applied only when it is the one the installed
    ///   session runs on.
    public func configure(config: PayabliConfig) {
        let transport: any PayabliTransport
        if let injectedTransport {
            entryPoint = config.entryPoint
            environment = config.environment
            transport = injectedTransport
        } else if let installed = PayabliSession.current, installed.matches(config) {
            entryPoint = config.entryPoint
            environment = config.environment
            session = installed
            reports = PayInReports(telemetry: installed.telemetry)
            transport = installed.transport
        } else {
            transport = RefusedTransport(refusal: PayabliGenericError(
                type: .invalidConfiguration,
                reason: "the configuration is not the one the session was initialized with"
            ))
        }
        client = PayInPaymentFlowClient(transport: transport)
        tokenStorageClient = PayInPaymentFlowTokenStorageClient(transport: transport)
    }

    public func configure(config: PayabliConfig, theme _: PayabliTheme) {
        configure(config: config)
    }

    public func configure(
        operation: PayabliPayInOperation,
        requestConfiguration: PayabliPayInRequestConfiguration? = nil
    ) {
        self.operation = operation
        self.requestConfiguration = requestConfiguration
    }

    public func configure(
        requestConfiguration: PayabliPayInRequestConfiguration
    ) {
        self.requestConfiguration = requestConfiguration
    }

    public func submitConfigured(
        _ request: PayabliPayInRequest
    ) async throws -> PayabliPayInResult {
        try await submitConfigured(request, origin: .direct)
    }

    public func submitConfigured(
        _ paymentMethod: PayabliPayInMethodInput,
        options: PayabliPayInTokenStorageOptions = PayabliPayInTokenStorageOptions()
    ) async throws -> PayabliPayInResult {
        try await submitConfigured(paymentMethod, options: options, origin: .direct)
    }

    /// Runs the configured operation on a payment, reported as started by `origin`.
    ///
    /// - Parameter request: the payment and its settings.
    /// - Parameter origin: whether the form or the host started it.
    /// - Returns: the result the service sent.
    func submitConfigured(
        _ request: PayabliPayInRequest,
        origin: PayInReports.Origin
    ) async throws -> PayabliPayInResult {
        switch operation {
        case .storePaymentMethod:
            try await reported(.storeMethod, origin: origin, method: PayInReports.method(of: request.paymentMethod)) {
                throw PayabliPayInError.invalidInput("A payment method input is required for storePaymentMethod.")
            }
        case .capture:
            try await capture(request, origin: origin)
        case .authorize:
            try await authorize(request, origin: origin)
        }
    }

    /// Stores a method when that is the configured operation, reported as started by `origin`.
    ///
    /// - Parameter paymentMethod: the card or bank account data to store.
    /// - Parameter options: what the request carries besides the method.
    /// - Parameter origin: whether the form or the host started it.
    /// - Returns: the stored method, as a result.
    func submitConfigured(
        _ paymentMethod: PayabliPayInMethodInput,
        options: PayabliPayInTokenStorageOptions,
        origin: PayInReports.Origin
    ) async throws -> PayabliPayInResult {
        guard operation == .storePaymentMethod else {
            return try await reported(
                operation == .capture ? .capture : .authorize,
                origin: origin,
                method: PayInReports.method(of: paymentMethod.method)
            ) {
                throw PayabliPayInError.invalidInput("storePaymentMethod operation is required to store a payment method.")
            }
        }

        let storedPaymentMethod = try await addPaymentMethod(paymentMethod, options: options, origin: origin)
        return PayabliPayInResult(storedPaymentMethod: storedPaymentMethod)
    }

    /// Reports a submission the form refused before handing it to the flow.
    ///
    /// - Parameter error: the refusal.
    /// - Parameter method: the kind of method the form was submitting.
    func reportFormRefusal(_ error: any Error, method: PayabliPayInMethodType) {
        let reported: PayInReports.Operation = switch operation {
        case .storePaymentMethod: .storeMethod
        case .capture: .capture
        case .authorize: .authorize
        }
        reports?.completed(reported, origin: .form, method: PayInReports.method(of: method), after: nil, error: error)
    }

    /// Stores card or bank account payment data using `POST /api/TokenStorage/add`.
    ///
    /// - Parameter paymentMethod: the card or bank account data to store.
    /// - Parameter options: what the request carries besides the method, from the customer to the flags.
    /// - Returns: the method the service stored, with its identifiers.
    public func addPaymentMethod(
        _ paymentMethod: PayabliPayInMethodInput,
        options: PayabliPayInTokenStorageOptions = PayabliPayInTokenStorageOptions()
    ) async throws -> PayabliPayInStoredPaymentMethod {
        try await addPaymentMethod(paymentMethod, options: options, origin: .direct)
    }

    private func addPaymentMethod(
        _ paymentMethod: PayabliPayInMethodInput,
        options: PayabliPayInTokenStorageOptions,
        origin: PayInReports.Origin
    ) async throws -> PayabliPayInStoredPaymentMethod {
        try await reported(.storeMethod, origin: origin, method: PayInReports.method(of: paymentMethod.method)) {
            try beginSubmission()
            defer { endSubmission() }

            let storedPaymentMethod = try await tokenStorageClient.addMethod(
                entryPoint: entryPoint,
                paymentMethod: paymentMethod,
                options: options
            )
            lastResult = PayabliPayInResult(storedPaymentMethod: storedPaymentMethod)
            return storedPaymentMethod
        }
    }

    public func addCard(
        _ card: PayabliPayInCardData,
        options: PayabliPayInTokenStorageOptions = PayabliPayInTokenStorageOptions()
    ) async throws -> PayabliPayInStoredPaymentMethod {
        try await addPaymentMethod(.card(card), options: options)
    }

    public func addBankAccount(
        _ ach: PayabliPayInBankAccountData,
        options: PayabliPayInTokenStorageOptions = PayabliPayInTokenStorageOptions()
    ) async throws -> PayabliPayInStoredPaymentMethod {
        try await addPaymentMethod(.bankAccount(ach), options: options)
    }

    /// Authorizes and captures a transaction in one step using
    /// `POST /api/v2/MoneyIn/getpaid`.
    ///
    /// Each call is a new payment unless its options declare `attempt` as `.retry`.
    ///
    /// - Parameter request: the payment and its settings.
    /// - Returns: the result the service sent.
    public func capture(
        _ request: PayabliPayInRequest
    ) async throws -> PayabliPayInResult {
        try await capture(request, origin: .direct)
    }

    private func capture(
        _ request: PayabliPayInRequest,
        origin: PayInReports.Origin
    ) async throws -> PayabliPayInResult {
        try await reported(.capture, origin: origin, method: PayInReports.method(of: request.paymentMethod)) {
            try await submit {
                let reference = try paymentReference(of: request)
                return try await sending(
                    .capture(reference: reference),
                    claimsHeld: request.options.attempt == .retry,
                    payment: HeldPaymentDescription(request),
                    reference: reference
                ) { key in
                    try await client.capture(entryPoint: entryPoint, request: request, idempotencyKey: key)
                }
            }
        }
    }

    /// Authorizes a card, a stored card, or a cloud-device reading using
    /// `POST /api/v2/MoneyIn/authorize`.
    ///
    /// Any other payment method is refused before anything is sent. Each call is a new payment unless its
    /// options declare `attempt` as `.retry`.
    ///
    /// - Parameter request: the payment and its settings, which must be taken by a card, a stored card
    ///   or a cloud-device reading.
    /// - Returns: the result the service sent.
    public func authorize(
        _ request: PayabliPayInRequest
    ) async throws -> PayabliPayInResult {
        try await authorize(request, origin: .direct)
    }

    private func authorize(
        _ request: PayabliPayInRequest,
        origin: PayInReports.Origin
    ) async throws -> PayabliPayInResult {
        try await reported(.authorize, origin: origin, method: PayInReports.method(of: request.paymentMethod)) {
            try await submit {
                let reference = try paymentReference(of: request)
                return try await sending(
                    .authorize(reference: reference),
                    claimsHeld: request.options.attempt == .retry,
                    payment: HeldPaymentDescription(request),
                    reference: reference
                ) { key in
                    try await client.authorize(entryPoint: entryPoint, request: request, idempotencyKey: key)
                }
            }
        }
    }

    /// Captures a prior authorization using
    /// `POST /api/v2/MoneyIn/capture/{transId}`.
    ///
    /// Calling again on a transaction whose capture ended with its outcome unknown sends the key held for it.
    ///
    /// - Parameter request: the authorization and the amount to capture.
    /// - Returns: the result the service sent.
    public func captureAuthorizedTransaction(
        _ request: PayabliPayInAuthorizedRequest
    ) async throws -> PayabliPayInResult {
        // The capture of an authorization is a capture; the authorization's method is not known here.
        try await reported(.capture, origin: .direct, method: nil) {
            try await submit {
                try await sending(
                    .captureAuthorized(transId: request.transId.payabliCaptureTrimmed),
                    claimsHeld: true
                ) { key in
                    try await client.captureAuthorized(request, idempotencyKey: key)
                }
            }
        }
    }

    /// Reverses a transaction using `POST /api/v2/MoneyIn/void/{transId}`, releasing an
    /// authorization's hold or undoing a capture that has not settled.
    ///
    /// Which transactions can still be reversed is the service's to decide, and is not mirrored here:
    /// a state it will not reverse comes back as the refusal it sent, carrying its own reason.
    ///
    /// The result is returned and not published: ``lastResult`` keeps whatever the last submission
    /// left there, so a caller reads the outcome here rather than waiting on that.
    ///
    /// Calling again on a transaction whose reversal ended with its outcome unknown sends the key held for it.
    ///
    /// - Parameter transId: the transaction to reverse, as
    ///   ``PayabliPayInTransaction/paymentTransId`` reported it.
    /// - Returns: the result the service sent.
    public func voidTransaction(
        _ transId: String
    ) async throws -> PayabliPayInResult {
        try await reported(.void, origin: .direct, method: nil) {
            try await exclusively {
                try await sending(
                    .void(transId: transId.payabliCaptureTrimmed),
                    claimsHeld: true
                ) { key in
                    try await client.void(transId: transId, idempotencyKey: key)
                }
            }
        }
    }

    /// Reads a transaction back by its identifier, to learn what a payment did.
    ///
    /// Moves no money, so it runs while a submission is in flight and leaves ``lastResult`` alone. A failed
    /// read is never ``PayabliPayInError/submissionInterrupted(type:causeType:paymentTransId:paymentReference:)``.
    /// `TRANSACTION_NOT_FOUND` means nothing is visible under the identifier yet, and `PERMISSION_DENIED` that
    /// this session may not read it.
    ///
    /// - Parameter transId: the transaction to read, as ``PayabliPayInTransaction/paymentTransId`` or an
    ///   interrupted submission's `paymentTransId` reported it.
    /// - Returns: the transaction, with its identifiers, method, amounts and ``PayabliPayInTransaction/status``.
    public func readTransaction(
        _ transId: String
    ) async throws -> PayabliPayInTransaction {
        try await reported(.read, origin: .direct, method: nil) {
            try await client.details(transId: transId)
        }
    }

    /// Runs an operation and reports how it ended, timed on the flow's clock.
    ///
    /// - Parameter operation: what runs.
    /// - Parameter origin: whether the form or the host started it.
    /// - Parameter method: the kind of payment method, or nil when the operation names none.
    /// - Parameter body: the operation.
    /// - Returns: what the operation returned.
    private func reported<Value>(
        _ operation: PayInReports.Operation,
        origin: PayInReports.Origin,
        method: String?,
        _ body: () async throws -> Value
    ) async throws -> Value {
        let startedAt = now()
        let refusal = PayInLocalRefusal()
        do {
            let value = try await PayInLocalRefusal.$current.withValue(refusal) { try await body() }
            reports?.completed(operation, origin: origin, method: method, after: now() - startedAt, error: nil)
            return value
        } catch {
            reports?.completed(
                operation,
                origin: origin,
                method: method,
                after: now() - startedAt,
                error: error,
                refusedLocally: refusal.wasRefused
            )
            // Converted after the report: the report names the type that failed, not the wrapper.
            throw error.payabliUnexpectedFailure ?? error
        }
    }

    /// Sends one attempt under the key it takes, and records what became of it.
    ///
    /// A money-moving request always carries a key: the held one when the attempt claims it, otherwise a new one.
    /// A refused held key reports ``PayabliErrorType/retryRefused``.
    ///
    /// - Parameter scope: what the attempt belongs to.
    /// - Parameter claimsHeld: whether the attempt takes the key held for its scope.
    /// - Parameter payment: the payment the attempt is for, compared with the held key's before taking it.
    /// - Parameter reference: the payment's reference, returned on an unknown outcome.
    /// - Parameter send: sends the request under the key it is given.
    /// - Returns: the result the service sent.
    private func sending(
        _ scope: HeldKeyScope,
        claimsHeld: Bool,
        payment: HeldPaymentDescription? = nil,
        reference: String? = nil,
        _ send: (String) async throws -> PayabliPayInResult
    ) async throws -> PayabliPayInResult {
        let reservation = try heldKeys.reserve(
            scope: scope,
            claimsHeld: claimsHeld,
            payment: payment,
            now: now(),
            mint: newIdempotencyKey
        )
        let mark = PayabliSendMark()
        // The submission around this one, such as the form's, learns whether the payment left.
        let submission = PayabliSendMark.current
        defer {
            if mark.mayHaveLeft {
                submission?.set()
            }
        }
        do {
            let result = try await PayabliSendMark.$current.withValue(mark) { try await send(reservation.key) }
            heldKeys.settle(reservation, outcome: .answered, now: now())
            return result
        } catch {
            var outcome = Self.outcome(of: error, reused: reservation.reused)
            if !mark.mayHaveLeft {
                outcome = .notAnswered
                if PayInReports.isRefusedBeforeSending(error) {
                    PayInLocalRefusal.current?.set()
                }
            }
            if heldKeys.settle(reservation, outcome: outcome, now: now()) {
                logger.warning("payin_retry_keys_full")
            }
            try Self.rethrow(
                error,
                as: outcome,
                reused: reservation.reused,
                mayHaveLeft: mark.mayHaveLeft,
                reference: reference
            )
        }
    }

    /// What a failed attempt means for its key.
    ///
    /// - Parameter error: what the attempt threw.
    /// - Parameter reused: whether the attempt sent a key held for an earlier one.
    /// - Returns: the outcome to settle the reservation with.
    private static func outcome(of error: any Error, reused: Bool) -> HeldIdempotencyKeys.Outcome {
        let open = error as? PayInOpenOutcome
        if let open, open.refusedKey {
            return reused ? .repeatRefused : .answered
        }
        switch open?.interruption ?? error as? PayabliPayInError {
        case let .submissionInterrupted(type, _, _, _):
            return type == .conflict ? .answered : .unknown
        case .invalidInput, .submissionInProgress, .missingAccessToken:
            return .notAnswered
        case .transactionFailed, nil:
            break
        }
        switch (error as? any PayabliError)?.type {
        case .paymentDeclined, .validation:
            return .answered
        default:
            return .notAnswered
        }
    }

    /// Throws a failure as the caller receives it: a definite outcome as itself, and
    /// ``PayabliPayInError/submissionInterrupted(type:causeType:paymentTransId:paymentReference:)`` whenever a send of
    /// this payment may have run.
    ///
    /// - Parameter error: what the attempt threw.
    /// - Parameter outcome: what it meant for the key.
    /// - Parameter reused: whether the attempt resent a held key, so an earlier send of this payment may have run.
    /// - Parameter mayHaveLeft: whether this send reached the HTTP layer.
    /// - Parameter reference: the payment's reference, which an unknown outcome carries.
    /// - Throws: the failure, with a refused held key reported as ``PayabliErrorType/retryRefused``.
    private static func rethrow(
        _ error: any Error,
        as outcome: HeldIdempotencyKeys.Outcome,
        reused: Bool,
        mayHaveLeft: Bool,
        reference: String?
    ) throws -> Never {
        if let open = error as? PayInOpenOutcome {
            guard reused || mayHaveLeft else { throw open.cause }
            guard case let .submissionInterrupted(type, causeType, paymentTransId, _) = open.interruption
            else { throw open.interruption }
            throw PayabliPayInError.submissionInterrupted(
                type: open.refusedKey && outcome == .repeatRefused ? .retryRefused : type,
                causeType: causeType,
                paymentTransId: paymentTransId,
                paymentReference: reference
            )
        }
        guard reused, outcome != .answered else { throw error }
        throw PayabliPayInError.submissionInterrupted(
            type: (error as? any PayabliError)?.type ?? .unknown,
            causeType: RedactedCause(error).originalType,
            paymentTransId: nil,
            paymentReference: reference
        )
    }

    /// The reference a capture or an authorization is held under: the host's, trimmed, or one made here.
    ///
    /// - Parameter request: the request whose options carry the host's payment reference.
    /// - Returns: the reference to hold the payment's key under.
    /// - Throws: ``PayabliPayInError/invalidInput(_:)`` when the host's reference is blank.
    private func paymentReference(of request: PayabliPayInRequest) throws -> String {
        guard let named = request.options.paymentReference else { return newPaymentReference() }
        guard let trimmed = named.payabliCaptureTrimmed.payabliCaptureNilIfEmpty else {
            throw PayabliPayInError.invalidInput("The payment reference cannot be blank.")
        }
        return trimmed
    }

    /// Runs one operation at a time and answers its caller, publishing nothing.
    ///
    /// The outcome reaches the caller through the member's return value, so the operation does not
    /// also replace ``lastResult``; the exclusion itself is kept either way.
    ///
    /// - Parameter operation: the operation to run under the exclusion.
    /// - Returns: the result the operation ended with.
    private func exclusively(
        _ operation: () async throws -> PayabliPayInResult
    ) async throws -> PayabliPayInResult {
        try beginSubmission()
        defer { endSubmission() }

        return try await operation()
    }

    /// Runs one operation at a time and publishes its result as the flow's last.
    ///
    /// For the operations a rendered form drives, where the screen observes the flow rather than
    /// holding a return value.
    ///
    /// - Parameter operation: the operation to run under the exclusion.
    /// - Returns: the result the operation ended with, published as ``lastResult``.
    private func submit(
        _ operation: () async throws -> PayabliPayInResult
    ) async throws -> PayabliPayInResult {
        // Inside the exclusion rather than after it, so the result is published before the
        // submission reports itself finished. The other way round, an observer woken by
        // `isSubmitting` going false reads the result of the submission before this one.
        try await exclusively {
            let result = try await operation()
            lastResult = result
            return result
        }
    }

    private func beginSubmission() throws {
        guard activeSubmissionCount == 0 else {
            throw PayabliPayInError.submissionInProgress
        }
        activeSubmissionCount = 1
        isSubmitting = true
    }

    private func endSubmission() {
        activeSubmissionCount = max(0, activeSubmissionCount - 1)
        isSubmitting = activeSubmissionCount > 0
    }
}
