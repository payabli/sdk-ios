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

    /// Brings a session back after it has expired, and does nothing if it has not.
    func reinitializeIfNeeded() async throws {
        try await run { try await terminal.reinitializeIfNeeded() }
    }

    /// Takes a sale. The returned string is the payment's transaction identifier,
    /// and `suppliesCustomer` names this app's stand-in customer on it.
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
        isAttestationRevoked = (error as? TapToPayError)?.type == .deviceSetupRequired
    }
}
