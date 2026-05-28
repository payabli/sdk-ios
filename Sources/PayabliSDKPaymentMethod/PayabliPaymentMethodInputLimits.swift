enum PayabliPaymentMethodInputLimits {
    static let minimumCardNumberDigits = 12
    static let maximumCardNumberDigits = 19
    static let maximumCardholderNameCharacters = 60
    static let minimumCardCvvDigits = 3
    static let maximumCardCvvDigits = 4
    static let maximumPostalCodeCharacters = 12
    static let achRoutingDigits = 9
    static let minimumACHAccountDigits = 4
    static let maximumACHAccountDigits = 17
    static let maximumACHHolderNameCharacters = 60
}
