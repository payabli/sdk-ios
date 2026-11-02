import Foundation

/// A payment method to store: the instrument, and the options for everything else.
public struct PayabliPayInStoreRequest: Sendable {
    public let instrument: PayabliPayInMethodInput
    public let options: PayabliPayInTokenStorageOptions

    /// Creates a store request.
    ///
    /// - Parameter instrument: the card or bank account data to store.
    /// - Parameter options: what the request carries besides the method, from the customer to the flags.
    public init(
        instrument: PayabliPayInMethodInput,
        options: PayabliPayInTokenStorageOptions
    ) {
        self.instrument = instrument
        self.options = options
    }
}
