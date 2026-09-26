import Foundation

/// Carries the configuration itself into a change handler, which may otherwise read the view's
/// previous value.
struct PayInPaymentFlowConfigurationChange: Equatable {
    let configuration: PayabliPayInFormConfiguration

    init(_ configuration: PayabliPayInFormConfiguration) {
        self.configuration = configuration
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.configuration.payabliViewModelSignature == rhs.configuration.payabliViewModelSignature
    }
}

extension PayabliPayInFormConfiguration {
    var payabliViewModelSignature: String {
        [
            "allowed:\(allowedMethods.map(\.rawValue).joined(separator: ","))",
            "default:\(defaultMethod.rawValue)",
            "cardFields:\(cardFieldOrder.map(\.rawValue).joined(separator: ","))",
            "achFields:\(bankFieldOrder.map(\.rawValue).joined(separator: ","))",
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

private extension PayabliPayInHiddenValues {
    var payabliViewModelSignature: String {
        [
            "achHolderType:\(accountHolderType?.rawValue ?? "")",
            "achSecCode:\(secCode?.rawValue ?? "")",
            "achDevice:\(deviceId ?? "")",
            "methodDescription:\(methodDescription ?? "")",
            "customerData:\(customerData.payabliJSONSignature)"
        ]
        .joined(separator: ",")
    }
}

private extension PayabliPayInLabels {
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

private extension PayabliPayInFormatting {
    var payabliViewModelSignature: String {
        [
            "spaces:\(insertsCardNumberSpaces)",
            "separator:\(expirationSeparator)",
            "masksACH:\(masksAccountNumber)"
        ]
        .joined(separator: ",")
    }
}

private extension PayabliPayInPaymentSummaryConfiguration {
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

private extension [PayabliPayInField: String] {
    var payabliViewModelSignature: String {
        map { "\($0.key.rawValue)=\($0.value)" }
            .sorted()
            .joined(separator: ",")
    }
}
