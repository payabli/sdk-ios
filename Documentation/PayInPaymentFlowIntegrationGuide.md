# PayabliSDKPayInPaymentFlow Integration Guide

## Store A Payment Method

```swift
@StateObject private var paymentFlow = PayabliPayInPaymentFlow(
    entryPoint: entryPoint,
    environment: .sandbox,
    accessTokenProvider: {
        try await backend.fetchPayInAccessToken()
    },
    operation: .storePaymentMethod
)
```

```swift
let stored = try await paymentFlow.addCard(PayabliPayInPaymentFlowCardData(
    cardNumber: "4111111111111111",
    expiration: "02/28",
    cardholderName: "Jane Doe",
    cvv: "123",
    billingZip: "33139"
))
```

For integrations that must avoid host-app access to clear PAN, render `PayabliPayInPaymentFlowView` or the SDK sheet instead of collecting card data and calling the direct APIs. Direct card APIs are PCI-sensitive because the host app supplies `PayabliPayInPaymentFlowCardData`.

## Capture Or Authorize

```swift
@StateObject private var paymentFlow = PayabliPayInPaymentFlow(
    entryPoint: entryPoint,
    environment: .sandbox,
    accessTokenProvider: {
        try await backend.fetchPayInAccessToken()
    },
    operation: .capture,
    requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration(
        paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
            totalAmount: 1.00,
            serviceFee: 0.10,
            currency: "USD"
        ),
        orderDescription: "iOS checkout",
        source: "ios-sdk",
        achValidation: true,
        forceCustomerCreation: true
    )
)
```

Use `.authorize` instead of `.capture` when the transaction should be authorized only. Authorize currently accepts card data only. ACH, stored payment methods, cash, check, and cloud-device payments are rejected for `.authorize`; Apple Pay can be added later as a separate authorizable method.

Capture a prior authorization with the direct API:

```swift
let result = try await paymentFlow.captureAuthorizedTransaction(
    PayabliPayInPaymentFlowAuthorizedRequest(
        transId: "authorized-transaction-id",
        paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
            totalAmount: 1.00,
            serviceFee: 0.10,
            currency: "USD"
        )
    )
)
```

## Sections, Placeholders, And Hidden Labels

```swift
let hiddenLabelFields: [PayabliPayInPaymentFlowField] = [
    .cardholderName,
    .cardNumber,
    .cardExpiration,
    .cardCvv,
    .cardZip
]

let config = PayabliPayInPaymentFlowFormConfiguration(
    allowedMethods: [.card, .ach],
    cardSections: [
        PayabliPayInPaymentFlowFieldSection(
            title: "Card Information",
            fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip],
            inputVerticalSpacing: 4,
            inputHorizontalSpacing: 8,
            fieldVerticalSpacings: [.cardNumber: 2, .cardCvv: 2]
        ),
        PayabliPayInPaymentFlowFieldSection(
            title: "Customer Information",
            fields: [.firstName, .lastName, .billingEmail]
        )
    ],
    labels: PayabliPayInPaymentFlowLabels(
        fieldPlaceholders: Dictionary(uniqueKeysWithValues: hiddenLabelFields.map {
            ($0, PayabliPayInPaymentFlowLabels.defaultFieldLabels[$0] ?? $0.rawValue)
        })
    ),
    showsFieldLabels: false,
    hiddenFieldLabels: Set(hiddenLabelFields)
)
```

## Styling

```swift
let style = PayabliPayInPaymentFlowStyle(
    accentColor: .blue,
    input: PayabliPayInPaymentFlowInputStyle(
        font: .body,
        uiFont: UIFont(name: "Inter-Regular", size: 16),
        textColor: .primary,
        placeholderColor: Color(uiColor: .placeholderText),
        backgroundColor: Color(uiColor: .systemBackground),
        cornerRadius: 8
    ),
    submitButton: PayabliPayInPaymentFlowSubmitButtonStyle(cornerRadius: 8),
    layout: PayabliPayInPaymentFlowLayoutStyle(
        contentSpacing: 18,
        fieldGroupSpacing: 8,
        pairedFieldSpacing: 12,
        sectionSpacing: 20
    )
)
```

Custom fonts must be provided by the host app through bundled font files and `UIAppFonts`.

## Bridge Scope

Flutter, React Native, and .NET MAUI bridge files currently expose stored card/ACH payment-method creation. Native Swift integrations should call `PayabliSDKPayInPaymentFlow` directly for capture, authorize, and capture-authorized transaction flows until those request models are added to the bridge APIs.

## Testing

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPayInPaymentFlowTests
```

Coverage report:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPayInPaymentFlowTests \
  -enableCodeCoverage YES \
  -resultBundlePath build/TestResults/PayInPaymentFlowCoverage.xcresult

xcrun xccov view --report build/TestResults/PayInPaymentFlowCoverage.xcresult
```
