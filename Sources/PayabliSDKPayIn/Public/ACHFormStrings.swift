import Foundation

/// Customizable, host-app-overridable strings for the ACH form.
///
/// Pass to `ACHFormView(strings:)` (or `.payabliAchSheet(strings:)`) to
/// localize or rebrand every visible string in the ACH form: field labels,
/// placeholders, picker option titles, validation errors, the
/// tokenization-mode submit-button title, and the sheet-chrome title.
///
/// ```swift
/// let strings = ACHFormStrings(
///     routingNumberLabel: "Numero de ruta",
///     accountNumberLabel: "Numero de cuenta"
/// )
/// ACHFormView(customerId: 4440, strings: strings) { token, error in
///     // ...
/// }
/// ```
public struct ACHFormStrings: Sendable {

    // MARK: - Sheet chrome

    /// Title shown by `.payabliAchSheet` in the sheet header.
    public var sheetTitle: String

    // MARK: - Field labels

    public var holderNameLabel: String
    public var routingNumberLabel: String
    public var accountNumberLabel: String
    public var accountTypeLabel: String
    public var holderTypeLabel: String

    // MARK: - Field placeholders

    public var holderNamePlaceholder: String
    public var routingNumberPlaceholder: String
    public var accountNumberPlaceholder: String

    // MARK: - Picker options

    public var accountTypeChecking: String
    public var accountTypeSavings: String
    public var holderTypePersonal: String
    public var holderTypeBusiness: String

    // MARK: - Submit button (tokenization mode)

    /// Submit-button title used in tokenization mode.
    /// Charge mode uses an automatically-formatted "Pay $X.XX" instead.
    public var saveButtonTitle: String

    // MARK: - Validation errors

    public var holderNameError: String
    public var routingNumberError: String
    public var accountNumberError: String

    public init(
        sheetTitle: String = "Bank account",
        holderNameLabel: String = "Account holder name",
        routingNumberLabel: String = "Routing number",
        accountNumberLabel: String = "Account number",
        accountTypeLabel: String = "Account type",
        holderTypeLabel: String = "Holder type",
        holderNamePlaceholder: String = "Jane Doe",
        routingNumberPlaceholder: String = "021000021",
        accountNumberPlaceholder: String = "Account number",
        accountTypeChecking: String = "Checking",
        accountTypeSavings: String = "Savings",
        holderTypePersonal: String = "Personal",
        holderTypeBusiness: String = "Business",
        saveButtonTitle: String = "Save Payment Method",
        holderNameError: String = "Account holder name is required",
        routingNumberError: String = "Invalid routing number",
        accountNumberError: String = "Invalid account number"
    ) {
        self.sheetTitle = sheetTitle
        self.holderNameLabel = holderNameLabel
        self.routingNumberLabel = routingNumberLabel
        self.accountNumberLabel = accountNumberLabel
        self.accountTypeLabel = accountTypeLabel
        self.holderTypeLabel = holderTypeLabel
        self.holderNamePlaceholder = holderNamePlaceholder
        self.routingNumberPlaceholder = routingNumberPlaceholder
        self.accountNumberPlaceholder = accountNumberPlaceholder
        self.accountTypeChecking = accountTypeChecking
        self.accountTypeSavings = accountTypeSavings
        self.holderTypePersonal = holderTypePersonal
        self.holderTypeBusiness = holderTypeBusiness
        self.saveButtonTitle = saveButtonTitle
        self.holderNameError = holderNameError
        self.routingNumberError = routingNumberError
        self.accountNumberError = accountNumberError
    }

    /// Default English strings.
    public static let `default` = ACHFormStrings()
}
