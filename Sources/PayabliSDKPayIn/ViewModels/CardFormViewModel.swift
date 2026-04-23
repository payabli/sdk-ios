import Foundation
import Combine

/// Form-level state for the card tokenization / payment form.
///
/// Implements on-blur validation and touched-field tracking (PRD FR-4.1, FR-4.2).
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
    @Published public var cardNumber: String = ""
    /// Expiration month (1-12).
    @Published public var expirationMonth: Int = 1
    /// Expiration year (full, e.g. 2027).
    @Published public var expirationYear: Int = Calendar.current
        .component(.year, from: Date())
    @Published public var cvv: String = ""
    @Published public var zip: String = ""

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
                ? nil : "Card holder name is required"

        case .cardNumber:
            return PaymentValidators.isValidCardNumber(cardNumber)
                ? nil : "Invalid card number"

        case .expiration:
            return PaymentValidators.isValidExpiration(
                month: expirationMonth,
                year: expirationYear
            ) ? nil : "Invalid expiration date"

        case .cvv:
            return PaymentValidators.isValidCVV(cvv, brand: cardBrand)
                ? nil : "Invalid CVV"

        case .zip:
            return PaymentValidators.isValidZIP(zip) ? nil : "Invalid ZIP code"
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

    public func endSubmission(error: String? = nil) {
        isSubmitting = false
        lastError = error
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
