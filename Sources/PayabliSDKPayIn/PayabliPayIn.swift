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
    /// ``voidTransaction(_:)`` leaves this as it was and returns its result to its caller.
    @Published public private(set) var lastResult: PayabliPayInResult?

    public var lastStoredPaymentMethod: PayabliPayInStoredMethod? {
        lastResult?.storedPaymentMethod
    }

    public private(set) var entryPoint: String
    public private(set) var environment: PayabliEnvironment
    /// Mints the key for an attempt that supplied none.
    var newIdempotencyKey: @Sendable () -> String = { UUID().uuidString }
    var newPaymentReference: @Sendable () -> String = { UUID().uuidString.lowercased() }
    var copyDigits: @Sendable (SensitiveDigits) -> SensitiveDigits = { SensitiveDigits.copy(of: $0) }
    /// Reads the clock a held key ages against. One that keeps counting while the device sleeps.
    var now: @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }

    private(set) var session: PayabliSession?
    private let injectedTransport: (any PayabliTransport)?
    private var client: PayInPaymentFlowClient
    private var tokenStorageClient: PayInPaymentFlowTokenStorageClient
    private var activeSubmissionCount = 0
    private let heldKeys = PayInKeyStore.process
    private let logger = PayabliLogger(category: .tokenization)
    /// Nil on a flow built on a bare transport without a telemetry client.
    private(set) var reports: PayInReports?

    /// Builds the flow on a session, which carries the credential and the transport that sends it.
    ///
    /// The entry point and the environment come from the session's configuration, so a flow and the
    /// session it runs on cannot disagree about which merchant or which host they are for.
    ///
    /// - Parameter session: The session the flow sends on.
    public init(session: PayabliSession) {
        self.entryPoint = session.config.entryPoint
        self.environment = session.config.environment
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
    /// - Parameter telemetry: where the flow reports its operations, nil to report nothing.
    init(
        entryPoint: String,
        environment: PayabliEnvironment,
        transport: any PayabliTransport,
        telemetry: TelemetryClient? = nil
    ) {
        self.entryPoint = entryPoint
        self.environment = environment
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

    /// Runs an operation on a payment, reported as started by `origin`.
    ///
    /// - Parameter request: the payment and its settings.
    /// - Parameter operation: the operation to run on it.
    /// - Parameter origin: whether the form or the host started it.
    /// - Returns: the result the service sent.
    func submitConfigured(
        _ request: PayabliPayInRequest,
        for operation: PayabliPayInOperation,
        origin: PayInReports.Origin
    ) async throws -> PayabliPayInResult {
        switch operation {
        case .storePaymentMethod:
            try await reported(.storeMethod, origin: origin, method: PayInReports.method(of: request.paymentMethod)) {
                throw PayabliPayInError.InvalidInput(field: nil, reason: "A payment method input is required for storePaymentMethod.")
            }
        case .capture:
            try await capture(request, origin: origin)
        case .authorize:
            try await authorize(request, origin: origin)
        }
    }

    /// Stores a method when that is the operation, reported as started by `origin`.
    ///
    /// - Parameter request: the payment method to store and what the request carries besides it.
    /// - Parameter operation: the operation the method is stored for.
    /// - Parameter origin: whether the form or the host started it.
    /// - Returns: the stored method, as a result.
    func submitConfigured(
        _ request: PayabliPayInStoreRequest,
        for operation: PayabliPayInOperation,
        origin: PayInReports.Origin
    ) async throws -> PayabliPayInResult {
        guard case .storePaymentMethod = operation else {
            return try await reported(
                PayInReports.operation(of: operation.kind),
                origin: origin,
                method: PayInReports.method(of: request.instrument.method)
            ) {
                throw PayabliPayInError.InvalidInput(
                    field: nil,
                    reason: "storePaymentMethod operation is required to store a payment method."
                )
            }
        }

        let storedMethod = try await storeMethod(request, origin: origin)
        return PayabliPayInResult(storedPaymentMethod: storedMethod)
    }

    /// Reports a submission the form refused before handing it to the flow.
    ///
    /// - Parameter error: the refusal.
    /// - Parameter method: the kind of method the form was submitting.
    /// - Parameter operation: the operation the form was submitting for.
    func reportFormRefusal(
        _ error: any Error,
        method: PayabliPayInMethodType,
        operation: PayabliPayInOperation.Kind
    ) {
        reports?.completed(
            PayInReports.operation(of: operation),
            origin: .form,
            method: PayInReports.method(of: method),
            after: nil,
            error: error
        )
    }

    /// Stores card or bank account payment data using `POST /api/TokenStorage/add`.
    ///
    /// - Parameter request: the payment method to store, and what the request carries besides it.
    /// - Returns: the method the service stored, with its identifiers.
    public func storeMethod(
        _ request: PayabliPayInStoreRequest
    ) async throws -> PayabliPayInStoredMethod {
        try await storeMethod(request, origin: .direct)
    }

    private func storeMethod(
        _ request: PayabliPayInStoreRequest,
        origin: PayInReports.Origin
    ) async throws -> PayabliPayInStoredMethod {
        let instrument = request.instrument.withCopiedDigitBuffers(using: copyDigits)
        defer { Self.close(instrument.sensitiveDigits) }
        return try await reported(.storeMethod, origin: origin, method: PayInReports.method(of: instrument.method)) {
            try beginSubmission()
            defer { endSubmission() }

            let storedMethod = try await tokenStorageClient.addMethod(
                entryPoint: entryPoint,
                paymentMethod: instrument,
                options: request.options
            )
            lastResult = PayabliPayInResult(storedPaymentMethod: storedMethod)
            return storedMethod
        }
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
        let request = request.withCopiedDigitBuffers(using: copyDigits)
        defer { Self.close(request.paymentMethod.sensitiveDigits) }
        return try await reported(.capture, origin: origin, method: PayInReports.method(of: request.paymentMethod)) {
            try await submit {
                let reference = try paymentReference(of: request)
                return try await sending(
                    .capture(reference: reference),
                    claimsHeld: request.options.attempt == .retry,
                    origin: origin,
                    payment: HeldPaymentDescription(request),
                    reference: reference
                ) { client, entry, key in
                    try await client.capture(entryPoint: entry, request: request, idempotencyKey: key)
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
        let request = request.withCopiedDigitBuffers(using: copyDigits)
        defer { Self.close(request.paymentMethod.sensitiveDigits) }
        return try await reported(.authorize, origin: origin, method: PayInReports.method(of: request.paymentMethod)) {
            try await submit {
                let reference = try paymentReference(of: request)
                return try await sending(
                    .authorize(reference: reference),
                    claimsHeld: request.options.attempt == .retry,
                    origin: origin,
                    payment: HeldPaymentDescription(request),
                    reference: reference
                ) { client, entry, key in
                    try await client.authorize(entryPoint: entry, request: request, idempotencyKey: key)
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
                    claimsHeld: true,
                    origin: .direct
                ) { client, _, key in
                    try await client.captureAuthorized(request, idempotencyKey: key)
                }
            }
        }
    }

    /// Reverses a transaction using `POST /api/v2/MoneyIn/void/{transId}`, releasing an
    /// authorization's hold or undoing a capture that has not settled.
    ///
    /// The service decides which transactions can still be reversed, and a refusal carries its own reason.
    ///
    /// ``lastResult`` is left as it was: the outcome is this call's return value.
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
                    claimsHeld: true,
                    origin: .direct
                ) { client, _, key in
                    try await client.void(transId: transId, idempotencyKey: key)
                }
            }
        }
    }

    /// Reads a transaction back by its identifier, to learn what a payment did.
    ///
    /// Moves no money, so it runs while a submission is in flight and leaves ``lastResult`` alone. A failed
    /// read is never ``PayabliPayInError/Unsettled``.
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
            // Converted after the report: the report names the type that failed, not the wrapper. A direct call keeps its
            // cancellation; the form reports one as its own failure.
            if PayInInterruption.isCancellation(error) {
                throw origin == .form ? PayabliPayInError.Interrupted() : CancellationError()
            }
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
    /// - Parameter origin: whether the form or the host started it, which decides how a cancellation ends.
    /// - Parameter payment: the payment the attempt is for, compared with the held key's before taking it.
    /// - Parameter reference: the payment's reference, returned on an unknown outcome.
    /// - Parameter send: sends the request with the client, to the entry point and under the key it is given.
    /// - Returns: the result the service sent.
    private func sending(
        _ scope: HeldKeyScope,
        claimsHeld: Bool,
        origin: PayInReports.Origin,
        payment: HeldPaymentDescription? = nil,
        reference: String? = nil,
        _ send: (PayInPaymentFlowClient, String, String) async throws -> PayabliPayInResult
    ) async throws -> PayabliPayInResult {
        // Sent and settled where it was reserved, though `configure(config:)` may move the flow while it sends.
        let (reservedEntry, reservedEnvironment, reservedClient) = (entryPoint, environment, client)
        let reservation = try heldKeys.reserve(
            entry: reservedEntry,
            environment: reservedEnvironment,
            scope: scope,
            claimsHeld: claimsHeld,
            payment: payment,
            now: now(),
            mint: newIdempotencyKey
        )
        if reservation.foundNoRoom {
            logger.warning("payin_retry_keys_full")
        }
        let mark = PayabliSendMark()
        // The submission around this one, such as the form's, learns whether the payment left.
        let submission = PayabliSendMark.current
        defer {
            if mark.mayHaveLeft {
                submission?.set()
            }
        }
        do {
            let result = try await PayabliSendMark.$current.withValue(mark) {
                try await send(reservedClient, reservedEntry, reservation.key)
            }
            heldKeys.settle(entry: reservedEntry, environment: reservedEnvironment, reservation, outcome: .answered)
            return result
        } catch {
            var outcome = Self.outcome(of: error, reused: reservation.reused)
            // A decline answers the payment even when its 401 lowered the mark.
            if !mark.mayHaveLeft, (error as? any PayabliError)?.type != .paymentDeclined {
                outcome = .notAnswered
                if PayInReports.isRefusedBeforeSending(error) {
                    PayInLocalRefusal.current?.set()
                }
            }
            heldKeys.settle(entry: reservedEntry, environment: reservedEnvironment, reservation, outcome: outcome)
            try Self.rethrow(
                error,
                as: outcome,
                reused: reservation.reused,
                mayHaveLeft: mark.mayHaveLeft,
                reference: reference,
                origin: origin
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
        switch open?.interruption ?? error {
        case let unsettled as PayabliPayInError.Unsettled:
            return unsettled.type == .conflict ? .answered : .unknown
        case is PayabliPayInError.InvalidInput, is PayabliPayInError.AlreadySubmitting:
            return .notAnswered
        default:
            break
        }
        switch (error as? any PayabliError)?.type {
        case .paymentDeclined, .validation:
            return .answered
        default:
            return .notAnswered
        }
    }

    /// Throws a failure as the caller receives it: a definite outcome as itself, a direct call's cancellation as
    /// `CancellationError`, and ``PayabliPayInError/Unsettled``
    /// for any other failure once a send of this payment may have run.
    ///
    /// - Parameter error: what the attempt threw.
    /// - Parameter outcome: what it meant for the key.
    /// - Parameter reused: whether the attempt resent a held key, so an earlier send of this payment may have run.
    /// - Parameter mayHaveLeft: whether this send reached the HTTP layer.
    /// - Parameter reference: the payment's reference, which an unknown outcome carries.
    /// - Parameter origin: whether the form or the host started the attempt.
    /// - Throws: the failure, with a refused held key reported as ``PayabliErrorType/retryRefused``.
    private static func rethrow(
        _ error: any Error,
        as outcome: HeldIdempotencyKeys.Outcome,
        reused: Bool,
        mayHaveLeft: Bool,
        reference: String?,
        origin: PayInReports.Origin
    ) throws -> Never {
        if origin == .direct, PayInInterruption.isCancellation((error as? PayInOpenOutcome)?.cause ?? error) {
            throw CancellationError()
        }
        if let open = error as? PayInOpenOutcome {
            guard reused || mayHaveLeft else { throw open.cause }
            let interruption = open.interruption
            throw PayabliPayInError.Unsettled(
                interruption,
                type: open.refusedKey && outcome == .repeatRefused ? .retryRefused : interruption.type,
                paymentReference: reference
            )
        }
        guard reused, outcome != .answered else { throw error }
        throw PayabliPayInError.Unsettled(
            type: PayInInterruption.type(of: error),
            cause: error,
            paymentTransId: nil,
            paymentReference: reference
        )
    }

    /// The reference a capture or an authorization is held under: the host's, trimmed, or for a new payment one
    /// made here.
    ///
    /// - Parameter request: the request whose options carry the host's payment reference.
    /// - Returns: the reference to hold the payment's key under.
    /// - Throws: ``PayabliPayInError/InvalidInput`` when the host's reference is blank, or when a retry names
    ///   none.
    private func paymentReference(of request: PayabliPayInRequest) throws -> String {
        guard let named = request.options.paymentReference else {
            guard request.options.attempt == .newPayment else {
                throw PayabliPayInError.InvalidInput(
                    field: PayInFieldPath.paymentReference,
                    reason: "A retry must name the paymentReference of the payment it repeats."
                )
            }
            return newPaymentReference()
        }
        guard let trimmed = named.payabliCaptureTrimmed.payabliCaptureNilIfEmpty else {
            throw PayabliPayInError.InvalidInput(field: PayInFieldPath.paymentReference, reason: "The paymentReference cannot be blank.")
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
    /// For the operations a rendered form drives, whose screen observes ``lastResult``.
    ///
    /// - Parameter operation: the operation to run under the exclusion.
    /// - Returns: the result the operation ended with, published as ``lastResult``.
    private func submit(
        _ operation: () async throws -> PayabliPayInResult
    ) async throws -> PayabliPayInResult {
        // Published inside the exclusion, so an observer woken by `isSubmitting` going false reads this result.
        try await exclusively {
            let result = try await operation()
            lastResult = result
            return result
        }
    }

    private func beginSubmission() throws {
        guard activeSubmissionCount == 0 else {
            throw PayabliPayInError.AlreadySubmitting()
        }
        activeSubmissionCount = 1
        isSubmitting = true
    }

    private func endSubmission() {
        activeSubmissionCount = max(0, activeSubmissionCount - 1)
        isSubmitting = activeSubmissionCount > 0
    }
}

extension PayabliPayIn {
    /// Overwrites a call's own digit buffers.
    ///
    /// - Parameter buffers: the buffers to close.
    static func close(_ buffers: [SensitiveDigits]) {
        for buffer in buffers {
            buffer.close()
        }
    }
}
