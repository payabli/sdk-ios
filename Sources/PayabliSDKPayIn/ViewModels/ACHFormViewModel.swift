import Foundation
import Combine

/// Form-level state for the ACH tokenization / payment form.
@MainActor
public final class ACHFormViewModel: ObservableObject {
    public enum Field: Hashable, CaseIterable {
        case holderName
        case routingNumber
        case accountNumber
    }

    // MARK: - Inputs

    @Published public var holderName: String = ""
    @Published public var routingNumber: String = ""
    @Published public var accountNumber: String = ""
    @Published public var accountType: ACHAccountType = .checking
    @Published public var holderType: ACHHolderType = .personal

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
                ? nil : "Account holder name is required"
        case .routingNumber:
            return PaymentValidators.isValidRoutingNumber(routingNumber)
                ? nil : "Invalid routing number"
        case .accountNumber:
            return PaymentValidators.isValidAccountNumber(accountNumber)
                ? nil : "Invalid account number"
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

    public func endSubmission(error: String? = nil) {
        isSubmitting = false
        lastError = error
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
