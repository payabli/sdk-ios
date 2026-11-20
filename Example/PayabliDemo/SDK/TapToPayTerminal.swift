import Combine
import Foundation
import os
import PayabliSDKTapToPay

/// A screen's grip on the card reader. A screen drives the terminal through these calls and reads its
/// state as ``TapToPaySessionStatus``.
@MainActor
final class TapToPayTerminal: ObservableObject {
    /// Where the reader has got to. Republished from the SDK's own state, mapped
    /// on the way out.
    @Published private(set) var status: TapToPaySessionStatus

    /// How far the reader has got configuring, from 0 to 100, or `nil` when it
    /// has not reported.
    ///
    /// How far the reader has got configuring, read off the session state.
    @Published private(set) var configurationProgress: Int?

    private let terminal: PayabliTTP
    private var forwarding: Set<AnyCancellable> = []

    init(_ terminal: PayabliTTP) {
        self.terminal = terminal
        status = TapToPaySessionStatus(terminal.sessionState)
        // This object holds the subscriptions, so they hold it weakly.
        terminal.$sessionState
            .map(TapToPaySessionStatus.init)
            .removeDuplicates()
            .sink { [weak self] status in
                self?.status = status
            }
            .store(in: &forwarding)

        terminal.$sessionState
            .map(\.readerConfigurationPercent)
            .removeDuplicates()
            .sink { [weak self] percent in
                self?.configurationProgress = percent
            }
            .store(in: &forwarding)
    }

    /// Attests the device, fetches its configuration and brings the reader up.
    func initialize() async throws {
        try await run { try await terminal.initialize() }
    }

    /// Takes a sale. The returned string is the payment's transaction identifier,
    /// and `suppliesCustomer` names this app's stand-in customer on it.
    func charge(amount: Decimal, suppliesCustomer: Bool) async throws -> String {
        try await run {
            let result = try await terminal.charge(
                paymentDetails: PayabliTTPPaymentDetails(amount: amount),
                customer: suppliesCustomer
                    ? TapToPayDemoCustomer.customerData
                    : TapToPayDemoCustomer.none,
                orderDescription: "Tap to Pay sample"
            )
            return result.paymentTransId
        }
    }

    /// Sends the close for a payment, in any session state.
    ///
    /// - Parameter paymentTransId: the payment to close.
    func close(paymentTransId: String) async throws {
        try await run { try await terminal.closeCapturedCharge(paymentTransId: paymentTransId) }
    }

    /// Presents an activation code for a device the service is holding.
    func activate(code: String) async throws {
        try await run { try await terminal.activateDevice(activationCode: code) }
    }

    /// The id a backend sends with the paypoint to issue this device's activation code, while one is owed.
    var activationId: String? {
        terminal.activationId
    }

    /// Asks the platform to present its terms so the merchant can accept them.
    ///
    /// Returning means the request completed, not that a sheet appeared, so the walk
    /// asks again afterwards rather than assuming either.
    func presentTerms() async throws {
        try await run { try await terminal.presentTerms() }
    }

    /// Whether the merchant has accepted, asked of the platform.
    func termsAccepted() async throws -> Bool {
        try await run { try await terminal.areTermsAccepted() }
    }

    // MARK: -

    /// One place where a failure becomes this app's own, so no caller sees a
    /// `TapToPayError` and every caller gets the same shape.
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            throw TapToPayFailure(error, session: TapToPaySessionStatus(terminal.sessionState))
        }
    }
}

/// Something the reader refused.
struct TapToPayFailure: DisplayedFailure, CodedFailure {
    let message: String
    let eventCode: String
    let isPendingActivation: Bool
    let isDeviceSetupRequired: Bool
    let isDeviceNotPending: Bool
    let isRefused: Bool
    let paymentTransId: String?

    init(_ error: Error, session: TapToPaySessionStatus) {
        let failure = error as? TapToPayError
        message = ActionLine.chargeMessage(
            for: error,
            capture: failure?.capture ?? .notCharged,
            paymentTransId: failure?.paymentTransId
        )
        eventCode = ActionLine.eventCode(for: error)
        Logger(subsystem: "com.payabli.example.app", category: "TapToPayDiagnostics")
            .error("Tap to Pay failed: \(LoggableError.label(for: error), privacy: .public)")
        isDeviceSetupRequired = failure?.type == .deviceSetupRequired
        isDeviceNotPending = failure?.type == .deviceNotPending
        isRefused = session == .refused
        isPendingActivation = session == .pendingActivation
        paymentTransId = failure?.paymentTransId
    }
}
