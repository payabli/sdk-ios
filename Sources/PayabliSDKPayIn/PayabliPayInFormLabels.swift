import Foundation
import PayabliSDKCore

public struct PayabliPayInFormLabels: Sendable {
    /// The form's heading; nil or blank draws none.
    public let title: String?
    public let subtitle: String?
    /// The submit button's wording; nil or blank reads the operation's own.
    public let submitButton: String?
    public let fieldLabels: [PayabliPayInField: String]
    public let fieldPlaceholders: [PayabliPayInField: String]
    /// The label on the summary's Total row; nil or blank reads "Total".
    public let total: String?
    /// The payer's message for a declined submission; nil or blank reads the SDK's own.
    public let declinedMessage: String?
    /// The payer's message when the same submission may work later; nil or blank reads the SDK's own.
    public let retryLaterMessage: String?
    /// The payer's message when a submission may have gone through; nil or blank reads the SDK's own.
    public let outcomeUnknownMessage: String?
    /// The payer's message for every failure category but the three named ones; nil or blank reads
    /// the SDK's own.
    public let otherMessage: String?

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        submitButton: String? = nil,
        fieldLabels: [PayabliPayInField: String] = Self.defaultFieldLabels,
        fieldPlaceholders: [PayabliPayInField: String] = [:],
        total: String? = nil,
        declinedMessage: String? = nil,
        retryLaterMessage: String? = nil,
        outcomeUnknownMessage: String? = nil,
        otherMessage: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.submitButton = submitButton
        self.fieldLabels = fieldLabels
        self.fieldPlaceholders = fieldPlaceholders
        self.total = total
        self.declinedMessage = declinedMessage
        self.retryLaterMessage = retryLaterMessage
        self.outcomeUnknownMessage = outcomeUnknownMessage
        self.otherMessage = otherMessage
    }

    /// The payer's message for a failure of one category, named as the error's own category is so a
    /// host that switches on it finds the same words here.
    ///
    /// - Parameter category: the failure category the message is drawn for.
    /// - Returns: the host's message, trimmed, or nil when it is absent or blank, in which case the
    ///   SDK's own message for the category is drawn.
    public func failureMessage(for category: PayabliErrorCategory) -> String? {
        let message: String? = switch category {
        case .declined:
            declinedMessage
        case .retryLater:
            retryLaterMessage
        case .outcomeUnknown:
            outcomeUnknownMessage
        case .credential, .configuration, .invalidRequest, .device, .internal:
            otherMessage
        }
        return message?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    /// The host's label for `field`, or the default when the host's is absent or blank.
    ///
    /// - Parameter field: the field whose label the form draws.
    /// - Returns: the label to draw: the host's, the default's, or the field's own name.
    public func label(for field: PayabliPayInField) -> String {
        fieldLabels[field].flatMap { Self.isBlank($0) ? nil : $0 }
            ?? Self.defaultFieldLabels[field]
            ?? field.rawValue
    }

    /// The heading to draw, trimmed, or nil when the host's is absent or blank.
    var drawnTitle: String? {
        title?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    /// The host's button wording, trimmed, or nil when it is absent or blank.
    var hostSubmitButton: String? {
        submitButton?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    /// Blank when every scalar is a space, line or paragraph separator, or a control in U+0009–U+000D or
    /// U+001C–U+001F.
    ///
    /// - Parameter text: the label or heading to test.
    /// - Returns: whether the text is blank.
    static func isBlank(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .spaceSeparator, .lineSeparator, .paragraphSeparator:
                return true
            default:
                return (0x09 ... 0x0D).contains(scalar.value) || (0x1C ... 0x1F).contains(scalar.value)
            }
        }
    }

    public func placeholder(for field: PayabliPayInField) -> String? {
        fieldPlaceholders[field]?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    public static let defaultFieldLabels: [PayabliPayInField: String] = [
        .cardholderName: "Name on card",
        .cardNumber: "Card number",
        .cardExpiration: "Expiration",
        .cardCvv: "CVV",
        .cardZip: "Postal code",
        .accountHolder: "Account holder",
        .routingNumber: "Routing number",
        .accountNumber: "Account number",
        .accountType: "Account type",
        .accountHolderType: "Holder type",
        .secCode: "SEC code",
        .deviceId: "Device",
        .methodDescription: "Description",
        .firstName: "First name",
        .lastName: "Last name",
        .customerNumber: "Customer number",
        .billingEmail: "Billing email",
        .billingZip: "Billing postal code",
        .amount: "Amount",
        .serviceFee: "Fee",
        .surchargeFee: "Surcharge"
    ]
}
