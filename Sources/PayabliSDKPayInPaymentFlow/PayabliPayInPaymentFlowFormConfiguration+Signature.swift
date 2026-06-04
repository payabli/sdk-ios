import Foundation

extension PayabliPayInPaymentFlowFormConfiguration {
    var payabliViewModelSignature: String {
        [
            "allowed:\(allowedMethods.map(\.rawValue).joined(separator: ","))",
            "default:\(defaultMethod.rawValue)",
            "cardFields:\(cardFieldOrder.map(\.rawValue).joined(separator: ","))",
            "achFields:\(achFieldOrder.map(\.rawValue).joined(separator: ","))",
            "hidden:\(hiddenValues.payabliViewModelSignature)",
            "options:\(options.payabliViewModelSignature)",
            "labels:\(labels.payabliViewModelSignature)",
            "formatting:\(formatting.payabliViewModelSignature)",
            "required:\(requiredFields.map(\.rawValue).sorted().joined(separator: ","))",
            "paymentSummary:\(paymentSummary.payabliViewModelSignature)"
        ]
        .joined(separator: "|")
    }
}

private extension PayabliPayInPaymentFlowHiddenValues {
    var payabliViewModelSignature: String {
        [
            "achHolderType:\(achHolderType?.rawValue ?? "")",
            "achSecCode:\(achSecCode?.rawValue ?? "")",
            "achDevice:\(achDevice ?? "")",
            "methodDescription:\(methodDescription ?? "")",
            "customerData:\(customerData.payabliJSONSignature)"
        ]
        .joined(separator: ",")
    }
}

private extension PayabliPayInPaymentFlowLabels {
    var payabliViewModelSignature: String {
        [
            "title:\(title)",
            "subtitle:\(subtitle ?? "")",
            "submit:\(submitButton)",
            "labels:\(fieldLabels.payabliViewModelSignature)",
            "placeholders:\(fieldPlaceholders.payabliViewModelSignature)"
        ]
        .joined(separator: "|")
    }
}

private extension PayabliPayInPaymentFlowFormatting {
    var payabliViewModelSignature: String {
        [
            "spaces:\(insertsCardNumberSpaces)",
            "separator:\(expirationSeparator)",
            "masksACH:\(masksACHAccountEntry)"
        ]
        .joined(separator: ",")
    }
}

private extension PayabliPayInPaymentFlowPaymentSummaryConfiguration {
    var payabliViewModelSignature: String {
        [
            "amountLabel:\(amountLabelText ?? "")",
            "amountValue:\(amountValueText ?? "")",
            "feeLabel:\(feeLabelText ?? "")",
            "feeValue:\(feeValueText ?? "")",
            "currency:\(currencySymbol)",
            "rowSpacing:\(rowSpacing)"
        ]
        .joined(separator: ",")
    }
}

private extension Dictionary where Key == PayabliPayInPaymentFlowField, Value == String {
    var payabliViewModelSignature: String {
        map { "\($0.key.rawValue)=\($0.value)" }
            .sorted()
            .joined(separator: ",")
    }
}
