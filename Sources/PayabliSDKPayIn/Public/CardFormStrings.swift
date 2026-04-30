import Foundation

/// Customizable, host-app-overridable strings for the card form.
///
/// Pass to `CardFormView(strings:)` (or `.payabliCardSheet(strings:)`) to
/// localize or rebrand every visible string in the card form: floating
/// labels, validation errors, the submit-button title for tokenization,
/// and the sheet-chrome title.
///
/// All fields default to the English copy used by Payabli's reference UI;
/// host apps only need to override the strings they want to customize.
///
/// ```swift
/// let strings = CardFormStrings(
///     cardNumberLabel: "Numero de tarjeta",
///     cvcLabel: "CVV"
/// )
/// CardFormView(customerId: 4440, strings: strings) { token, error in
///     // ...
/// }
/// ```
public struct CardFormStrings: Sendable {

    // MARK: - Sheet chrome

    /// Title shown by `.payabliCardSheet` in the sheet header.
    public var sheetTitle: String

    // MARK: - Field labels

    public var holderNameLabel: String
    public var cardNumberLabel: String
    public var expirationLabel: String
    public var cvcLabel: String
    public var zipLabel: String

    // MARK: - Submit button (tokenization mode)

    /// Submit-button title used in tokenization mode.
    /// Charge mode uses an automatically-formatted "Pay $X.XX" instead.
    public var saveButtonTitle: String

    // MARK: - Validation errors

    public var holderNameError: String
    public var cardNumberError: String
    public var expirationError: String
    public var cvcError: String
    public var zipError: String

    /// Shown when the detected brand is not in `allowedBrands`.
    public var disallowedBrandError: String

    public init(
        sheetTitle: String = "Card details",
        holderNameLabel: String = "Card holder name",
        cardNumberLabel: String = "Card number",
        expirationLabel: String = "MM / YY",
        cvcLabel: String = "CVC",
        zipLabel: String = "ZIP",
        saveButtonTitle: String = "Save payment method",
        holderNameError: String = "Card holder name is required",
        cardNumberError: String = "Invalid card number",
        expirationError: String = "Invalid expiration date",
        cvcError: String = "Invalid CVC",
        zipError: String = "Invalid ZIP code",
        disallowedBrandError: String = "Card brand not accepted"
    ) {
        self.sheetTitle = sheetTitle
        self.holderNameLabel = holderNameLabel
        self.cardNumberLabel = cardNumberLabel
        self.expirationLabel = expirationLabel
        self.cvcLabel = cvcLabel
        self.zipLabel = zipLabel
        self.saveButtonTitle = saveButtonTitle
        self.holderNameError = holderNameError
        self.cardNumberError = cardNumberError
        self.expirationError = expirationError
        self.cvcError = cvcError
        self.zipError = zipError
        self.disallowedBrandError = disallowedBrandError
    }

    /// Default English strings.
    public static let `default` = CardFormStrings()
}
