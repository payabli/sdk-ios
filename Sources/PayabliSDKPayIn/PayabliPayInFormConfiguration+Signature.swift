import Foundation

/// Joins a signature's components with each carrying its own length, so wording that holds the
/// separators, or another component's name, cannot take a component's place.
///
/// - Parameter components: the rendered components one signature is built from.
/// - Returns: the components joined so the join reads one way only.
func payabliFramedSignature(_ components: [String]) -> String {
    components.map { "\($0.utf8.count):\($0)" }.joined()
}

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
        payabliFramedSignature([
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
        ])
    }
}

private extension PayabliPayInHiddenValues {
    var payabliViewModelSignature: String {
        payabliFramedSignature([
            "achHolderType:\(accountHolderType?.rawValue ?? "")",
            "achSecCode:\(secCode?.rawValue ?? "")",
            "achDevice:\(deviceId ?? "")",
            "methodDescription:\(methodDescription ?? "")",
            "customerData:\(customerData.payabliJSONSignature)"
        ])
    }
}

extension PayabliPayInFormLabels {
    var payabliViewModelSignature: String {
        payabliFramedSignature([
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
        ])
    }
}

private extension PayabliPayInFormatting {
    var payabliViewModelSignature: String {
        payabliFramedSignature([
            "spaces:\(insertsCardNumberSpaces)",
            "separator:\(expirationSeparator)",
            "masksACH:\(masksAccountNumber)"
        ])
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
        payabliFramedSignature(
            map { "\($0.key.rawValue)=\($0.value)" }
                .sorted()
        )
    }
}
