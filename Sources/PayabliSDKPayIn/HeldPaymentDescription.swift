import Foundation
import PayabliSDKCore

/// The payment a held key was made for, so a retry sends that key only for the same payment.
///
/// Kept in memory beside the key and dropped with it. It names an amount, so it never prints its fields.
struct HeldPaymentDescription: Equatable, CustomStringConvertible {
    /// What kind of method the payment is taken from, without the method's details.
    enum MethodKind: Equatable {
        case card
        case bank
        case check
        case cash
    }

    private let total: Decimal
    private let serviceFee: Decimal
    private let surchargeFee: Decimal
    private let currency: String?
    private let methodKind: MethodKind
    private let orderId: String?

    /// - Parameter request: the request an attempt sends.
    init(_ request: PayabliPayInRequest) {
        total = Self.asSent(request.paymentDetails.totalAmount)
        serviceFee = Self.asSent(request.paymentDetails.serviceFee ?? 0)
        surchargeFee = Self.asSent(request.paymentDetails.surchargeFee ?? 0)
        currency = request.paymentDetails.currency?.payabliCaptureTrimmed.uppercased().payabliCaptureNilIfEmpty
        methodKind = Self.kind(of: request.paymentMethod)
        orderId = request.options.orderId?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    var description: String {
        "HeldPaymentDescription(redacted)"
    }

    /// Whether a retry describing `retry` repeats this payment.
    ///
    /// - Parameter retry: the payment the retry describes.
    /// - Returns: whether every compared field agrees; an order identifier counts only when this payment set one.
    func isRepeated(by retry: Self) -> Bool {
        total == retry.total
            && serviceFee == retry.serviceFee
            && surchargeFee == retry.surchargeFee
            && currency == retry.currency
            && methodKind == retry.methodKind
            && (orderId == nil || orderId == retry.orderId)
    }

    /// The amount as the request carries it, or as given when it cannot be sent at all.
    private static func asSent(_ amount: Double) -> Decimal {
        PayInAmount.sendable(amount) ?? Decimal(string: String(amount)) ?? .nan
    }

    private static func kind(of method: PayabliPayInPaymentMethod) -> MethodKind {
        switch method {
        case .card, .cloudDevice: .card
        case .bankAccount: .bank
        case let .stored(stored): stored.method == .card ? .card : .bank
        case .check: .check
        case .cash: .cash
        }
    }
}
