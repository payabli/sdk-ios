import Foundation

/// Carries the configuration and the labels into a change handler, which may otherwise read the
/// view's previous values.
struct PayInPaymentFlowConfigurationChange: Equatable {
    let configuration: PayabliPayInFormConfiguration
    let labels: PayabliPayInFormLabels

    init(_ configuration: PayabliPayInFormConfiguration, labels: PayabliPayInFormLabels) {
        self.configuration = configuration
        self.labels = labels
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.configuration.payabliViewModelSignature == rhs.configuration.payabliViewModelSignature
            && lhs.labels.payabliViewModelSignature == rhs.labels.payabliViewModelSignature
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
            "formatting:\(formatting.payabliViewModelSignature)",
            "required:\(requiredFields.map(\.rawValue).sorted().joined(separator: ","))",
            "paymentSummary:\(paymentSummary.payabliViewModelSignature)",
            "showsBaseAmount:\(showsBaseAmount)",
            "showsFailureMessage:\(showsFailureMessage)"
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

extension PayabliPayInFormLabels {
    var payabliViewModelSignature: String {
        [
            "title:\(title ?? "")",
            "subtitle:\(subtitle ?? "")",
            "submit:\(submitButton ?? "")",
            "labels:\(fieldLabels.payabliViewModelSignature)",
            "placeholders:\(fieldPlaceholders.payabliViewModelSignature)",
            "total:\(total ?? "")",
            "declined:\(declinedMessage ?? "")",
            "retryLater:\(retryLaterMessage ?? "")",
            "outcomeUnknown:\(outcomeUnknownMessage ?? "")",
            "other:\(otherMessage ?? "")"
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
