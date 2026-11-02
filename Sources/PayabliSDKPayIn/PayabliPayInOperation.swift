import Foundation

/// What the form does with what a payer entered.
///
/// A payment carries everything it sends except the payment method, so a form can be set up before the payer
/// has typed anything.
public enum PayabliPayInOperation: Sendable {
    /// Stores the payment method, so a later payment charges it without the details again. The options are
    /// everything the stored method is sent with besides the details the payer enters.
    case storePaymentMethod(PayabliPayInStoreOptions = PayabliPayInStoreOptions())
    /// Takes the payment the configuration describes.
    case capture(PayabliPayInRequestConfiguration)
    /// Places a hold for the payment the configuration describes without taking it. Card only.
    case authorize(PayabliPayInRequestConfiguration)
}

extension PayabliPayInOperation {
    /// Which operation this is, without what it carries.
    enum Kind: String, CaseIterable, Sendable {
        case storePaymentMethod
        case capture
        case authorize
    }

    var kind: Kind {
        switch self {
        case .storePaymentMethod: .storePaymentMethod
        case .capture: .capture
        case .authorize: .authorize
        }
    }

    /// What a stored method is sent with, or nil when the operation sends a payment instead.
    var storeOptions: PayabliPayInStoreOptions? {
        switch self {
        case let .storePaymentMethod(options): options
        case .capture, .authorize: nil
        }
    }

    /// The payment this operation sends, or nil when it stores a method instead.
    var requestConfiguration: PayabliPayInRequestConfiguration? {
        switch self {
        case .storePaymentMethod: nil
        case let .capture(configuration), let .authorize(configuration): configuration
        }
    }

    var payabliViewModelSignature: String {
        payabliFramedSignature([
            "kind:\(kind.rawValue)",
            "request:\(requestConfiguration?.payabliViewModelSignature ?? "")",
            "store:\(storeOptions?.payabliViewModelSignature ?? "")"
        ])
    }
}
