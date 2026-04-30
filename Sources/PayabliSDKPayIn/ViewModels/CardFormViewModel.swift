import Foundation
import Combine
import PayabliSDKCore

/// Form-level state for the card tokenization / payment form.
///
/// Implements on-blur validation and touched-field tracking (PRD FR-4.1, FR-4.2),
/// live PAN auto-formatting ("4242 4242 4242 4242" — Amex "XXXX XXXXXX XXXXX"),
/// and CVV length capping based on the detected brand.
@MainActor
public final class CardFormViewModel: ObservableObject {
    public enum Field: Hashable, CaseIterable {
        case holderName
        case cardNumber
        case expiration
        case cvv
        case zip
    }

    // MARK: - Inputs

    @Published public var holderName: String = ""

    /// Card number. Auto-formats with brand-appropriate spaces as the user types.
    @Published public var cardNumber: String = "" {
        didSet {
            let digits = cardNumber.filter(\.isNumber)
            let brand = PaymentValidators.cardBrand(for: digits)
            let capped = String(digits.prefix(PaymentValidators.maxDigits(for: brand)))
            let formatted = PaymentValidators.formatCardNumber(capped, brand: brand)
            if formatted != cardNumber {
                cardNumber = formatted
            }
        }
    }

    /// Expiration month (1-12).
    @Published public var expirationMonth: Int = 1
    /// Expiration year (full, e.g. 2027).
    @Published public var expirationYear: Int = Calendar.current
        .component(.year, from: Date())

    /// Inline "MM / YY" expiration text. Auto-formats as the user types
    /// (digits-only, slash inserted after the 2nd digit) and keeps
    /// `expirationMonth` / `expirationYear` in sync.
    @Published public var expirationText: String = "" {
        didSet {
            let digits = String(expirationText.filter(\.isNumber).prefix(4))
            let formatted: String
            switch digits.count {
            case 0, 1, 2:
                formatted = String(digits)
            default:
                let mm = digits.prefix(2)
                let yy = digits.dropFirst(2)
                formatted = "\(mm) / \(yy)"
            }
            if formatted != expirationText {
                expirationText = formatted
            }
            if digits.count >= 2, let m = Int(digits.prefix(2)) {
                expirationMonth = m
            }
            if digits.count == 4, let y = Int(digits.suffix(2)) {
                expirationYear = 2000 + y
            }
        }
    }

    /// CVV. Capped to brand-appropriate length (Amex = 4, others = 3).
    @Published public var cvv: String = "" {
        didSet {
            let digits = cvv.filter(\.isNumber)
            let maxLength = PaymentValidators.cvvLength(for: cardBrand)
            let capped = String(digits.prefix(maxLength))
            if capped != cvv {
                cvv = capped
            }
        }
    }

    @Published public var zip: String = ""

    // MARK: - Configuration
    //
    // `strings` and `allowedBrands` are populated by the `CardFormView` on
    // first appear. They drive (1) localized error copy and (2) brand
    // restriction. Defaults match the unconfigured/test path.

    /// Localized copy used for field labels and validation errors.
    @Published public var strings: CardFormStrings = .default

    /// Set of card brands the form will accept. Defaults to `.all`.
    /// PANs whose detected brand is outside this set fail validation with
    /// `strings.disallowedBrandError`.
    @Published public var allowedBrands: PayabliCardBrand = .all

    // MARK: - State

    @Published public private(set) var touchedFields: Set<Field> = []
    @Published public private(set) var isSubmitting: Bool = false
    @Published public private(set) var lastError: String?

    // MARK: - Derived

    /// The detected brand from `cardNumber`. Updates as the user types.
    public var cardBrand: PaymentValidators.CardBrand {
        PaymentValidators.cardBrand(for: cardNumber)
    }

    /// Returns the validation error for a field, or nil when valid.
    /// Only returns a non-nil value when the field has been touched (FR-4.2).
    public func errorMessage(for field: Field) -> String? {
        guard touchedFields.contains(field) else { return nil }
        return validate(field: field)
    }

    /// Validates a field in isolation, ignoring touched state.
    public func validate(field: Field) -> String? {
        switch field {
        case .holderName:
            return PaymentValidators.isValidHolderName(holderName)
                ? nil : strings.holderNameError

        case .cardNumber:
            // Brand restriction takes precedence over Luhn — surfacing
            // "brand not accepted" is more actionable than "invalid number"
            // for a PAN that is otherwise well-formed but unsupported.
            if !allowedBrands.allows(cardBrand) {
                return strings.disallowedBrandError
            }
            return PaymentValidators.isValidCardNumber(cardNumber)
                ? nil : strings.cardNumberError

        case .expiration:
            return PaymentValidators.isValidExpiration(
                month: expirationMonth,
                year: expirationYear
            ) ? nil : strings.expirationError

        case .cvv:
            return PaymentValidators.isValidCVV(cvv, brand: cardBrand)
                ? nil : strings.cvcError

        case .zip:
            return PaymentValidators.isValidZIP(zip) ? nil : strings.zipError
        }
    }

    /// Whether the form passes all validation rules. Drives submit-button enabled state (FR-4.4).
    public var isValid: Bool {
        Field.allCases.allSatisfy { validate(field: $0) == nil }
    }

    // MARK: - Actions

    /// Marks a field as touched (user focused and moved away).
    public func markTouched(_ field: Field) {
        touchedFields.insert(field)
    }

    /// Sets submitting state and clears any prior error.
    public func beginSubmission() {
        isSubmitting = true
        lastError = nil
    }

    /// Ends the submission. Pass `nil` for success, an `Error` for failure —
    /// the VM translates it to a user-facing string for `lastError`.
    public func endSubmission(error: Error? = nil) {
        isSubmitting = false
        lastError = error.map(Self.userFacingMessage(from:))
    }

    private static func userFacingMessage(from error: Error) -> String {
        if let payment = error as? PayabliPaymentError {
            return payment.asPayabliError.reason
        }
        if let payabli = error as? PayabliError {
            return payabli.reason
        }
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return "Request failed. Please try again."
    }

    /// Produces the formatted "MMYY" expiration string required by the API.
    public var expirationString: String {
        let mm = String(format: "%02d", expirationMonth)
        let yy = String(format: "%02d", expirationYear % 100)
        return mm + yy
    }

    /// Constructs the tokenization payload. Caller must validate form first.
    public func makePayload() -> CardTokenizationPayload {
        CardTokenizationPayload(
            cardnumber: cardNumber.filter(\.isNumber),
            cardexp: expirationString,
            cardcvv: cvv.filter(\.isNumber),
            cardHolder: holderName.trimmingCharacters(in: .whitespacesAndNewlines),
            cardzip: zip.filter(\.isNumber)
        )
    }
}
