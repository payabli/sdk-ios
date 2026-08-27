import PayabliSDKPayInPaymentFlow

/// What this app hands the SDK's form, for one operation.
///
/// Two values because the SDK separates them: the configuration is what to
/// collect, the style is how it is drawn. A screen holds one of these and names
/// neither type.
///
/// It also carries what the form is for, because a failure reads differently on
/// each: only a capture sends an idempotency key, so only a capture can be
/// answered from an attempt that already reached the service.
struct PayInFormSetup {
    let operation: PayInOperation
    let configuration: PayabliPayInPaymentFlowFormConfiguration
    let style: PayabliPayInPaymentFlowStyle
}

/// What a form is for.
enum PayInOperation {
    /// Store an instrument for later. Sends no idempotency key.
    case storedMethod
    /// Take a payment now, under a key that makes a resubmission a retry.
    case capture
}

/// The two forms this app shows.
///
/// Written the way an integrator would write them: the fields and sections they
/// want, and the wording they want. Everything the two have in common is in
/// ``PayInSharedConfiguration``, so a difference between them here is deliberate.
enum PayInForms {
    /// Store an instrument and get a reusable token back. No amount: nothing is
    /// being charged.
    static var storedMethod: PayInFormSetup {
        PayInFormSetup(
            operation: .storedMethod,
            configuration: PayabliPayInPaymentFlowFormConfiguration(
                allowedMethods: PayInSharedConfiguration.allowedMethods,
                defaultMethod: PayInSharedConfiguration.defaultMethod,
                cardFieldOrder: PayInSharedConfiguration.cardFieldOrder,
                achFieldOrder: PayInSharedConfiguration.achFieldOrder,
                cardSections: [
                    sectionTitled("Card Information", fields: [
                        .cardholderName,
                        .cardNumber,
                        .cardExpiration,
                        .cardCvv,
                        .cardZip
                    ]),
                    sectionTitled("Customer Information", fields: storedMethodCustomerFields)
                ],
                achSections: [
                    sectionTitled("Bank Information", fields: [
                        .achHolder,
                        .achRouting,
                        .achAccount,
                        .achAccountType
                    ]),
                    sectionTitled("Customer Information", fields: storedMethodCustomerFields)
                ],
                hiddenValues: PayabliPayInPaymentFlowHiddenValues(
                    achHolderType: .personal,
                    achSecCode: .web,
                    methodDescription: QAIdentity.current.note("save")
                ),
                options: PayabliPayInPaymentFlowOptions(
                    // Not sent at all, which is what the Android sample's store options
                    // do and what the paypoint's own setting then decides. Sending
                    // `false` would have the sample opt out of a check on an
                    // integrator's behalf.
                    createAnonymous: false,
                    forceCustomerCreation: true,
                    temporary: false,
                    source: "ios-payment-method-qa"
                ),
                labels: PayabliPayInPaymentFlowLabels(
                    title: "Save Payment Method",
                    subtitle: "Create a card or ACH token.",
                    fieldPlaceholders: placeholders
                ),
                labelLayout: PayInSharedConfiguration.labelLayout,
                showsFieldLabels: PayInSharedConfiguration.showsFieldLabels,
                hiddenFieldLabels: Set(PayInSharedConfiguration.fieldsWithHiddenLabels),
                formatting: PayInSharedConfiguration.formatting,
                inputSizing: PayInSharedConfiguration.inputSizing,
                cardBrandIconPlacement: PayInSharedConfiguration.cardBrandIconPlacement
            ),
            style: PayInSharedConfiguration.style
        )
    }

    /// Take a payment now. Carries the amount and the service fee, and a summary
    /// under the fields.
    static var capture: PayInFormSetup {
        PayInFormSetup(
            operation: .capture,
            configuration: PayabliPayInPaymentFlowFormConfiguration(
                allowedMethods: PayInSharedConfiguration.allowedMethods,
                defaultMethod: PayInSharedConfiguration.defaultMethod,
                cardFieldOrder: PayInSharedConfiguration.cardFieldOrder,
                achFieldOrder: PayInSharedConfiguration.achFieldOrder,
                cardSections: [
                    sectionTitled("Card Information", fields: [
                        .cardholderName,
                        .cardNumber,
                        .cardExpiration,
                        .cardCvv,
                        .cardZip
                    ]),
                    sectionTitled("Customer Information", fields: captureCustomerFields),
                    sectionTitled("Payment Information", fields: [.amount, .serviceFee])
                ],
                achSections: [
                    sectionTitled("Bank Information", fields: [
                        .achHolder,
                        .achRouting,
                        .achAccount,
                        .achAccountType
                    ]),
                    sectionTitled("Customer Information", fields: captureCustomerFields),
                    sectionTitled("Payment Information", fields: [.amount, .serviceFee])
                ],
                hiddenValues: PayabliPayInPaymentFlowHiddenValues(
                    achHolderType: .personal,
                    achSecCode: .web,
                    // What a transaction list shows as the note, and what names the device that sent it. Here
                    // rather than only on the request configuration because this value wins over that one: the
                    // component merges the form's description over the request's before it sends.
                    methodDescription: QAIdentity.current.note("capture")
                ),
                labels: PayabliPayInPaymentFlowLabels(
                    title: "Payment Capture",
                    subtitle: "Submit a card or ACH payment.",
                    submitButton: "Submit Payment",
                    fieldPlaceholders: placeholders
                ),
                labelLayout: PayInSharedConfiguration.labelLayout,
                showsFieldLabels: PayInSharedConfiguration.showsFieldLabels,
                hiddenFieldLabels: Set(PayInSharedConfiguration.fieldsWithHiddenLabels),
                formatting: PayInSharedConfiguration.formatting,
                inputSizing: PayInSharedConfiguration.inputSizing,
                cardBrandIconPlacement: PayInSharedConfiguration.cardBrandIconPlacement,
                paymentSummary: PayabliPayInPaymentFlowPaymentSummaryConfiguration(
                    labelStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle(
                        font: .subheadline,
                        color: .secondary
                    ),
                    valueStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle(
                        font: .subheadline.weight(.semibold),
                        color: .primary
                    ),
                    rowSpacing: 6
                )
            ),
            style: PayInSharedConfiguration.style
        )
    }

    // MARK: -

    /// A stored method belongs to a customer, and the number is what a later charge
    /// finds it by. The capture form leaves it out for the opposite reason: nothing
    /// is being stored against a customer there.
    private static let storedMethodCustomerFields: [PayabliPayInPaymentFlowField] = [
        .firstName,
        .lastName,
        .customerNumber,
        .billingEmail
    ]

    private static let captureCustomerFields: [PayabliPayInPaymentFlowField] = [
        .firstName,
        .lastName,
        .billingEmail
    ]

    private static var placeholders: [PayabliPayInPaymentFlowField: String] {
        PayInSharedConfiguration.labelMatchingPlaceholders(
            for: PayInSharedConfiguration.fieldsWithHiddenLabels
        )
    }

    /// Every section is titled the same way, so the wording is the only thing a
    /// caller states.
    private static func sectionTitled(
        _ title: String,
        fields: [PayabliPayInPaymentFlowField]
    ) -> PayabliPayInPaymentFlowFieldSection {
        PayabliPayInPaymentFlowFieldSection(
            title: title,
            titleStyle: PayInSharedConfiguration.sectionTitleStyle,
            fields: fields
        )
    }
}
