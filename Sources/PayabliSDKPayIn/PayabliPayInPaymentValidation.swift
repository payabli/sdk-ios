import Foundation

extension PayabliPayInPaymentMethod {
    func validate(_ validation: PayabliPayInValidation) throws {
        switch self {
        case let .card(method):
            try PayabliPayInMethodInput.card(method.data).validate(validation)
        case let .bankAccount(method):
            try PayabliPayInMethodInput.bankAccount(method.data).validate(validation)
        case let .stored(method):
            guard !method.storedMethodId.payabliCaptureTrimmed.isEmpty else {
                throw PayabliPayInError.InvalidInput(
                    field: PayInFieldPath.method(.storedMethodId),
                    reason: "Stored payment method ID is required."
                )
            }
        case let .cloudDevice(method):
            guard !method.device.payabliCaptureTrimmed.isEmpty else {
                throw PayabliPayInError.InvalidInput(field: PayInFieldPath.method(.device), reason: "Cloud device is required.")
            }
        case let .check(method):
            guard !method.holderName.payabliCaptureTrimmed.isEmpty else {
                throw PayabliPayInError.InvalidInput(
                    field: PayInFieldPath.method(.achHolder),
                    reason: "Check account holder is required."
                )
            }
        case .cash:
            break
        }
    }
}

extension PayabliPayInPaymentDetails {
    /// Each amount is checked as it is sent, at two places, so a total of `0.001`, sent as `0.00`, is refused.
    ///
    /// A negative surcharge, or a service fee and surcharge that together reach the total, cannot be charged,
    /// so it is refused before sending, from the form and from a direct call.
    func validate() throws {
        guard let total = PayInAmount.sendable(totalAmount) else {
            throw PayabliPayInError.InvalidInput(field: PayInFieldPath.totalAmount, reason: "Total amount is out of range.")
        }
        guard total > 0 else {
            throw PayabliPayInError.InvalidInput(field: PayInFieldPath.totalAmount, reason: "Total amount must be greater than 0.")
        }
        if let serviceFee {
            guard let fee = PayInAmount.sendable(serviceFee) else {
                throw PayabliPayInError.InvalidInput(field: PayInFieldPath.serviceFee, reason: "Service fee is out of range.")
            }
            guard fee >= 0 else {
                throw PayabliPayInError.InvalidInput(field: PayInFieldPath.serviceFee, reason: "Service fee cannot be negative.")
            }
        }
        if let surchargeFee {
            guard let surcharge = PayInAmount.sendable(surchargeFee) else {
                throw PayabliPayInError.InvalidInput(field: PayInFieldPath.surchargeFee, reason: "Surcharge is out of range.")
            }
            guard surcharge >= 0 else {
                throw PayabliPayInError.InvalidInput(field: PayInFieldPath.surchargeFee, reason: "Surcharge cannot be negative.")
            }
        }
        let fees = (serviceFee.flatMap(PayInAmount.sendable) ?? 0) + (surchargeFee.flatMap(PayInAmount.sendable) ?? 0)
        guard fees < total else {
            throw PayabliPayInError.InvalidInput(
                field: PayInFieldPath.totalAmount,
                reason: "Service fee and surcharge must be less than the total amount."
            )
        }
    }
}
