extension SensitiveDigits {
    /// A second buffer over the same digits. Closing either forks the storage they share, so the other
    /// keeps its digits until it is closed or released in turn.
    ///
    /// - Parameter digits: the buffer to copy.
    /// - Returns: the copy.
    static func copy(of digits: SensitiveDigits) -> SensitiveDigits {
        .of(digits.read())
    }
}

extension PayabliPayInRequest {
    /// This request with a method whose digit buffers the call holds alone, so the call can close them
    /// on every exit and leave the host's value whole for a later call.
    ///
    /// - Parameter copy: how each buffer is copied.
    /// - Returns: the request, its method's digits in buffers of the call's own.
    func withCopiedDigitBuffers(using copy: (SensitiveDigits) -> SensitiveDigits) -> PayabliPayInRequest {
        PayabliPayInRequest(paymentMethod: paymentMethod.withCopiedDigitBuffers(using: copy), options: options)
    }
}

extension PayabliPayInPaymentMethod {
    var sensitiveDigits: [SensitiveDigits] {
        switch self {
        case let .card(card): [card.data.cardNumber, card.data.securityCode]
        case let .bankAccount(account): [account.data.accountNumber]
        case .stored, .cloudDevice, .check, .cash: []
        }
    }

    /// A copy of this method whose digit buffers it holds alone: closing the copy or this method
    /// leaves the other's digits readable, because a close forks the storage they shared.
    ///
    /// - Parameter copy: how each buffer is copied.
    /// - Returns: the copy, with payloads that hold no digits passed through unchanged.
    func withCopiedDigitBuffers(
        using copy: (SensitiveDigits) -> SensitiveDigits = SensitiveDigits.copy(of:)
    ) -> PayabliPayInPaymentMethod {
        switch self {
        case let .card(card):
            .card(PayabliPayInPaymentMethod.Card(
                data: card.data.withCopiedDigitBuffers(using: copy),
                initiator: card.initiator,
                saveIfSuccess: card.saveIfSuccess
            ))
        case let .bankAccount(account):
            .bankAccount(PayabliPayInPaymentMethod.BankAccount(data: account.data.withCopiedDigitBuffers(using: copy)))
        case .stored, .cloudDevice, .check, .cash:
            self
        }
    }
}

extension PayabliPayInMethodInput {
    var sensitiveDigits: [SensitiveDigits] {
        switch self {
        case let .card(data): [data.cardNumber, data.securityCode]
        case let .bankAccount(data): [data.accountNumber]
        }
    }

    /// A copy of this input whose digit buffers it holds alone, as the payment method's copy does.
    ///
    /// - Parameter copy: how each buffer is copied.
    /// - Returns: the copy.
    func withCopiedDigitBuffers(using copy: (SensitiveDigits) -> SensitiveDigits) -> PayabliPayInMethodInput {
        switch self {
        case let .card(data): .card(data.withCopiedDigitBuffers(using: copy))
        case let .bankAccount(data): .bankAccount(data.withCopiedDigitBuffers(using: copy))
        }
    }
}

private extension PayabliPayInCardData {
    func withCopiedDigitBuffers(using copy: (SensitiveDigits) -> SensitiveDigits) -> PayabliPayInCardData {
        PayabliPayInCardData(
            cardNumber: copy(cardNumber),
            expiryMonth: expiryMonth,
            expiryYear: expiryYear,
            securityCode: copy(securityCode),
            holderName: holderName,
            postalCode: postalCode
        )
    }
}

private extension PayabliPayInBankAccountData {
    func withCopiedDigitBuffers(using copy: (SensitiveDigits) -> SensitiveDigits) -> PayabliPayInBankAccountData {
        PayabliPayInBankAccountData(
            accountNumber: copy(accountNumber),
            routingNumber: routingNumber,
            accountType: accountType,
            holderName: holderName,
            holderType: holderType,
            secCode: secCode
        )
    }
}
