import Foundation
import PayabliSDKCore

/// What the card-not-present flow reports about each operation it runs, through its session's client.
///
/// Reports run in order off the caller's path, each stamped with the time it is made. No instrument or payer data.
@MainActor
final class PayInReports {
    enum Operation {
        case capture
        case authorize
        case storeMethod
        case void
        case read

        var event: String {
            switch self {
            case .capture: TelemetryEventName.payinCaptureCompleted
            case .authorize: TelemetryEventName.payinAuthorizeCompleted
            case .storeMethod: TelemetryEventName.payinStoreMethodCompleted
            case .void: TelemetryEventName.payinVoidCompleted
            case .read: TelemetryEventName.payinReadCompleted
            }
        }
    }

    /// Whether the SDK-drawn form submitted the operation or the host called the member.
    enum Origin: String {
        case form
        case direct
    }

    private let telemetry: TelemetryClient
    private var tail: Task<Void, Never>?

    init(telemetry: TelemetryClient) {
        self.telemetry = telemetry
    }

    /// Reports an operation that ran, by how it ended.
    ///
    /// - Parameter operation: what ran.
    /// - Parameter origin: who started it.
    /// - Parameter method: the kind of payment method, or nil when the operation names none.
    /// - Parameter duration: how long it took; a refusal before anything was sent carries none.
    /// - Parameter error: what it threw, or nil when it succeeded.
    func completed(
        _ operation: Operation,
        origin: Origin,
        method: String?,
        after duration: Duration?,
        error: (any Error)?
    ) {
        let now = Date()
        let outcome = error.map(Self.outcome(of:)) ?? "approved"
        var properties = ["outcome": outcome, "origin": origin.rawValue]
        if let method {
            properties["method"] = method
        }
        // A second submission refused while one runs is counted by its outcome alone.
        if let error, !Self.isSingleFlightRefusal(error) {
            let told = (error as? any PayabliError)
                ?? PayabliGenericError(type: Self.isCancellation(error) ? .userCancelled : .unknown, reason: "")
            properties["code"] = told.type.rawValue
            properties["error_number"] = String(told.code)
            properties["failure_type"] = Self.failureType(of: error)
        }
        if outcome != "refused_locally", let duration {
            properties["duration_ms"] = Self.milliseconds(duration)
        }
        enqueue { [properties] in await $0.emit(operation.event, properties: properties, occurredAt: now) }
    }

    /// Waits until every report made so far has reached the client, and every send it started has ended.
    func sent() async {
        await tail?.value
        await telemetry.settled()
    }

    /// The `method` a payment reports: a channel such as cash or a cloud device names no instrument, so reports none.
    ///
    /// - Parameter method: the payment's method.
    /// - Returns: `card`, `bank` or `check`, or nil.
    static func method(of method: PayabliPayInPaymentMethod) -> String? {
        switch method {
        case .card: "card"
        case .bankAccount: "bank"
        case let .stored(stored): self.method(of: stored.method)
        case .check: "check"
        case .cash, .cloudDevice: nil
        }
    }

    /// The `method` a stored method reports.
    ///
    /// - Parameter type: the method's kind.
    /// - Returns: `card` or `bank`.
    static func method(of type: PayabliPayInStoredMethodType) -> String {
        switch type {
        case .card: "card"
        case .bankAccount: "bank"
        }
    }

    /// The `method` a method being stored reports.
    ///
    /// - Parameter type: the method's kind.
    /// - Returns: `card` or `bank`.
    static func method(of type: PayabliPayInMethodType) -> String {
        switch type {
        case .card: "card"
        case .bankAccount: "bank"
        }
    }

    /// How an operation that threw ended, keyed on what the caller was told.
    ///
    /// - Parameter error: what the operation threw.
    /// - Returns: `refused_locally`, `refused`, `declined`, `interrupted` or `failed`.
    static func outcome(of error: any Error) -> String {
        if isCancellation(error) {
            return "interrupted"
        }
        if isRefusedBeforeSending(error) {
            return "refused_locally"
        }
        switch (error as? any PayabliError)?.type {
        // Checked after the local refusals, which share this type: here it is the service refusing a field.
        case .validation: return "refused"
        case .paymentDeclined: return "declined"
        case .userCancelled: return "interrupted"
        case .invalidConfiguration, .retryNotSamePayment, .paymentReferenceOpen: return "refused_locally"
        default: return "failed"
        }
    }

    private static func isRefusedBeforeSending(_ error: any Error) -> Bool {
        switch error {
        case PayabliPayInError.invalidInput, PayabliPayInError.submissionInProgress,
             PayabliPayInTokenStorageError.invalidInput:
            true
        default:
            false
        }
    }

    private static func isSingleFlightRefusal(_ error: any Error) -> Bool {
        if case PayabliPayInError.submissionInProgress = error {
            return true
        }
        return false
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError {
            return true
        }
        guard case let PayabliPayInError.submissionInterrupted(_, causeType, _, _) = error else { return false }
        return simpleName(causeType) == "CancellationError"
    }

    /// The simple name of the type the SDK converted, never a message or a cause chain.
    ///
    /// - Parameter error: what the operation threw.
    /// - Returns: the converted type's name, or the thrown type's when nothing was converted.
    static func failureType(of error: any Error) -> String {
        if case let PayabliPayInError.submissionInterrupted(_, causeType, _, _) = error {
            return simpleName(causeType)
        }
        return String(describing: type(of: error))
    }

    /// Drops every module and enclosing-type qualifier, generic arguments included, as `String(describing:)` spells it.
    private static func simpleName(_ qualified: String) -> String {
        qualified.replacingOccurrences(of: #"[A-Za-z_][A-Za-z0-9_]*\."#, with: "", options: .regularExpression)
    }

    private func enqueue(_ report: @escaping @Sendable (TelemetryClient) async -> Void) {
        let previous = tail
        let telemetry = telemetry
        tail = Task {
            await previous?.value
            await report(telemetry)
        }
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}
