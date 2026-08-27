import Combine
import Foundation
import PayabliSDKTapToPay

/// A screen's grip on the card reader.
///
/// The terminal itself stays in here, and so does every state and error type it
/// publishes. A screen drives it through these four calls and reads
/// ``TapToPaySessionStatus``, so nothing outside this group names an SDK type for
/// the card-present surface.
@MainActor
final class TapToPayTerminal: ObservableObject {
    /// Where the reader has got to. Republished from the SDK's own state, mapped
    /// on the way out.
    @Published private(set) var status: TapToPaySessionStatus

    private let terminal: PayabliTTP
    private var forwarding: AnyCancellable?

    init(_ terminal: PayabliTTP) {
        self.terminal = terminal
        status = TapToPaySessionStatus(terminal.sessionState)
        // This object holds the subscription, so the subscription holds it weakly.
        forwarding = terminal.$sessionState
            .map(TapToPaySessionStatus.init)
            .removeDuplicates()
            .sink { [weak self] status in
                self?.status = status
            }
    }

    /// Attests the device, fetches its configuration and brings the reader up.
    func initialize() async throws {
        try await run { try await terminal.initialize() }
    }

    /// Brings a session back after it has expired, and does nothing if it has not.
    func reinitializeIfNeeded() async throws {
        try await run { try await terminal.reinitializeIfNeeded() }
    }

    /// Takes a sale. The returned string is the payment's transaction identifier.
    ///
    /// - Parameter suppliesCustomer: whether the sale names this app's stand-in
    ///   customer, which the app's switch decides.
    func charge(amount: Decimal, suppliesCustomer: Bool) async throws -> String {
        try await run {
            let result = try await terminal.charge(
                type: .sale,
                paymentDetails: PayabliTTPPaymentDetails(amount: amount),
                customer: suppliesCustomer
                    ? TapToPayDemoCustomer.customerData
                    : TapToPayDemoCustomer.none,
                orderDescription: "Tap to Pay sample"
            )
            return result.paymentTransId
        }
    }

    /// Presents an activation code for a device the service is holding.
    func activate(code: String) async throws {
        try await run { try await terminal.activateDevice(activationCode: code) }
    }

    /// Listens for the reader's own events, already named and flattened.
    func addEventListener(
        _ onEvent: @escaping (TapToPayEvent) -> Void
    ) -> TapToPayEventSubscription {
        let token = terminal.addEventListener { code, payload in
            let detail = payload.count == 0
                ? ""
                : payload.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", ")
            onEvent(TapToPayEvent(label: TapToPayEvent.name(for: code), detail: detail))
        }
        return TapToPayEventSubscription(token)
    }

    // MARK: -

    /// One place where a failure becomes this app's own, so no caller sees a
    /// `PayabliTTPError` and every caller gets the same shape.
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            throw TapToPayFailure(error)
        }
    }
}

/// Something the reader refused.
///
/// `LocalizedError`, because the screens show `localizedDescription`. Without it
/// Foundation answers a generic "operation couldn't be completed" for a struct
/// error and the reason the reader gave never reaches the payer.
struct TapToPayFailure: LocalizedError {
    /// Displayable, and what a screen shows.
    let message: String

    var errorDescription: String? {
        message
    }

    /// Whether the binding this device held has been revoked. A revoked
    /// attestation resets the session to idle, and the way out is a fresh cold
    /// attestation rather than another activation code.
    let isAttestationRevoked: Bool

    init(_ error: Error) {
        message = error.localizedDescription
        if let ttpError = error as? PayabliTTPError, case .attestationRevoked = ttpError {
            isAttestationRevoked = true
        } else {
            isAttestationRevoked = false
        }
    }
}

/// One line of the reader's event log.
struct TapToPayEvent {
    let label: String
    let detail: String

    /// `PayabliTTPEventCode` is an `@objc Int` enum, so `String(describing:)`
    /// renders `PayabliTTPEventCode(rawValue: 0)` rather than the case name.
    static func name(for code: PayabliTTPEventCode) -> String {
        switch code {
        case .attestationStarted: return "attestationStarted"
        case .attestationCompleted: return "attestationCompleted"
        case .configReceived: return "configReceived"
        case .readerInitializing: return "readerInitializing"
        case .readerReady: return "readerReady"
        case .chargeInitiated: return "chargeInitiated"
        case .nfcStarted: return "nfcStarted"
        case .nfcCompleted: return "nfcCompleted"
        case .nfcFailed: return "nfcFailed"
        case .updateCompleted: return "updateCompleted"
        case .updateFailed: return "updateFailed"
        case .sessionExpired: return "sessionExpired"
        case .reinitializeStarted: return "reinitializeStarted"
        case .reinitializeCompleted: return "reinitializeCompleted"
        case .devicePendingActivation: return "devicePendingActivation"
        case .activationStarted: return "activationStarted"
        case .activationCompleted: return "activationCompleted"
        case .activationFailed: return "activationFailed"
        case .attestationFailed: return "attestationFailed"
        case .configFailed: return "configFailed"
        @unknown default: return "event(\(code.rawValue))"
        }
    }
}

/// A listener's own tear-down.
///
/// It owns both the subscription and its cancellation, because a detached task
/// over the event stream would leak across view appearances: SwiftUI gives no
/// handle to cancel one.
final class TapToPayEventSubscription {
    private var token: PayabliTTPEventToken?

    init(_ token: PayabliTTPEventToken) {
        self.token = token
    }

    func cancel() {
        token?.cancel()
        token = nil
    }
}
