import Foundation
import PayabliSDKCore

/// The payment each entry point under each environment has read a card for and not confirmed a close on, in memory
/// only. Every terminal shares ``process``, so a payment one terminal holds is the one another closes.
///
/// Held once the reader answers, whatever it answered, until its close is confirmed or the next payment opens.
package final class HeldPayments: @unchecked Sendable {
    /// The store every terminal in this process uses.
    package static let process = HeldPayments()

    private let lock = NSLock()
    private var held: [String: HeldPayment] = [:]

    package init() {}

    /// Holds `payment` for `entry` under `environment`, in place of any payment held there.
    ///
    /// - Parameter payment: the payment whose card was read.
    /// - Parameter entry: the entry point the payment was opened on.
    /// - Parameter environment: the environment the payment was opened in.
    func hold(_ payment: HeldPayment, entry: String, environment: PayabliEnvironment) {
        lock.withLock { held[Self.slot(entry, environment)] = payment }
    }

    /// The payment held for `entry` under `environment`, when it is the one `paymentTransId` names.
    ///
    /// - Parameter paymentTransId: the payment a close names.
    /// - Parameter entry: the entry point the close is for.
    /// - Parameter environment: the environment the close is sent to.
    /// - Returns: the held payment, or `nil` when none is held there or another one is.
    func payment(named paymentTransId: String, entry: String, environment: PayabliEnvironment) -> HeldPayment? {
        lock.withLock {
            guard let payment = held[Self.slot(entry, environment)], payment.paymentTransId == paymentTransId else {
                return nil
            }
            return payment
        }
    }

    /// Drops the payment held for `entry` under `environment` when it is the one `paymentTransId` names, because its
    /// close was confirmed.
    ///
    /// - Parameter paymentTransId: the payment whose close was confirmed.
    /// - Parameter entry: the entry point it was opened on.
    /// - Parameter environment: the environment it was opened in.
    func drop(_ paymentTransId: String, entry: String, environment: PayabliEnvironment) {
        lock.withLock {
            let slot = Self.slot(entry, environment)
            if held[slot]?.paymentTransId == paymentTransId {
                held[slot] = nil
            }
        }
    }

    /// Drops whatever payment is held for `entry` under `environment`, because the next payment there opened.
    ///
    /// - Parameter entry: the entry point the new payment opened on.
    /// - Parameter environment: the environment it opened in.
    func dropAny(entry: String, environment: PayabliEnvironment) {
        lock.withLock { held[Self.slot(entry, environment)] = nil }
    }

    private static func slot(_ entry: String, _ environment: PayabliEnvironment) -> String {
        "\(environment.name)\u{0}\(entry)"
    }
}

/// A payment whose card was read and whose close was not confirmed: what a failed close reports, and the key a
/// confirmed close settles. Its description names neither the payment nor the key.
struct HeldPayment: CustomStringConvertible {
    let paymentTransId: String
    let outcome: CardReadOutcome
    let key: String
    /// Whether ``key`` was held for an earlier charge and resent.
    let resentKey: Bool

    /// What the reader's answer says about the money. A decline under a resent key says nothing about the earlier
    /// charge that key names, so it is unknown.
    var capture: PayabliTTPCapture {
        switch outcome {
        case .approved: .charged
        case .declined: resentKey ? .unknown : .notCharged
        case .indeterminate: .unknown
        }
    }

    /// Whether a confirmed close settles ``key``: only a fresh key, and only for an answer that was definite.
    var closeSettlesKey: Bool {
        !resentKey && outcome != .indeterminate
    }

    var description: String {
        "HeldPayment(outcome: \(outcome), resentKey: \(resentKey))"
    }
}
