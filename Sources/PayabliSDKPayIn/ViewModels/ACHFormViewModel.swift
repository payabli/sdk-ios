import Foundation
import Combine
import PayabliSDKCore

/// Form-level state for the ACH tokenization / payment form.
@MainActor
public final class ACHFormViewModel: ObservableObject {
    public enum Field: Hashable, CaseIterable {
        case holderName
        case routingNumber
        case accountNumber
    }

    /// ABA routing numbers are always exactly 9 digits (PRD §10).
    public static let routingLength = 9

    /// ACH account numbers cap at 17 digits in the NACHA spec.
    public static let accountMaxLength = 17

    // MARK: - Inputs

    @Published public var holderName: String = ""

    /// Routing number. Strips non-digits and caps at 9 digits as the user types.
    @Published public var routingNumber: String = "" {
        didSet {
            let digits = String(routingNumber.filter(\.isNumber).prefix(Self.routingLength))
            if digits != routingNumber { routingNumber = digits }
        }
    }

    /// Account number. Strips non-digits and caps at the NACHA max (17 digits).
    @Published public var accountNumber: String = "" {
        didSet {
            let digits = String(accountNumber.filter(\.isNumber).prefix(Self.accountMaxLength))
            if digits != accountNumber { accountNumber = digits }
        }
    }

    @Published public var accountType: ACHAccountType = .checking
    @Published public var holderType: ACHHolderType = .personal

    // MARK: - Configuration

    /// Localized copy used for field labels, placeholders, and validation
    /// errors. Populated by `ACHFormView` on first appear; defaults to
    /// English for the unconfigured/test path.
    @Published public var strings: ACHFormStrings = .default

    // MARK: - State

    @Published public private(set) var touchedFields: Set<Field> = []
    @Published public private(set) var isSubmitting: Bool = false
    @Published public private(set) var lastError: String?

    // MARK: - Validation

    public func errorMessage(for field: Field) -> String? {
        guard touchedFields.contains(field) else { return nil }
        return validate(field: field)
    }

    public func validate(field: Field) -> String? {
        switch field {
        case .holderName:
            return PaymentValidators.isValidHolderName(holderName)
                ? nil : strings.holderNameError
        case .routingNumber:
            return PaymentValidators.isValidRoutingNumber(routingNumber)
                ? nil : strings.routingNumberError
        case .accountNumber:
            return PaymentValidators.isValidAccountNumber(accountNumber)
                ? nil : strings.accountNumberError
        }
    }

    public var isValid: Bool {
        Field.allCases.allSatisfy { validate(field: $0) == nil }
    }

    // MARK: - Actions

    public func markTouched(_ field: Field) {
        touchedFields.insert(field)
    }

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

    public func makePayload() -> ACHTokenizationPayload {
        ACHTokenizationPayload(
            achAccount: accountNumber.filter(\.isNumber),
            achRouting: routingNumber.filter(\.isNumber),
            achAccountType: accountType,
            achHolder: holderName.trimmingCharacters(in: .whitespacesAndNewlines),
            achHolderType: holderType
        )
    }
}
