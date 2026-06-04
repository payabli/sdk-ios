# PayabliSDKPayInPaymentFlow LLM Guide

This file is the canonical local guide for generating code against `PayabliSDKPayInPaymentFlow`.

## Summary

`PayabliSDKPayInPaymentFlow` is the current unified PayIn form and API component for stored payment methods, capture, and authorization.

Do not import or suggest removed PayIn component products.

Use:

```swift
import PayabliSDKPayInPaymentFlow
```

Core public types are prefixed with `PayabliPayInPaymentFlow`, including:

- `PayabliPayInPaymentFlow`
- `PayabliPayInPaymentFlowView`
- `PayabliPayInPaymentFlowFormConfiguration`
- `PayabliPayInPaymentFlowStyle`
- `PayabliPayInPaymentFlowSheetConfiguration`
- `PayabliPayInPaymentFlowResult`
- `PayabliPayInPaymentFlowRequestConfiguration`
- `PayabliPayInPaymentFlowPaymentDetails`
- `PayabliPayInPaymentFlowCardData`
- `PayabliPayInPaymentFlowACHData`
- `PayabliPayInPaymentFlowOptions`

## Operations

`PayabliPayInPaymentFlowOperation` values:

- `.storePaymentMethod`
- `.capture`
- `.authorize`

The default operation is `.storePaymentMethod`.

`storePaymentMethod` sends card or ACH data to `/api/TokenStorage/add`.

`capture` and `authorize` submit MoneyIn v2 requests using the configured operation. These operations require `PayabliPayInPaymentFlowRequestConfiguration` for form submission.

`authorize` accepts card data only today. Do not generate ACH, stored-method, cash, check, or cloud-device authorization code. The component has a separate authorization-method capability enum so Apple Pay or another future authorizable method can be added later without treating every capture method as authorizable.

`captureAuthorizedTransaction(_:)` captures a prior authorization by transaction ID through `/api/v2/MoneyIn/capture/{transId}`. It is a direct API and is not rendered as a hosted form mode.

Use the component’s mobile access-token provider for all operations. Do not add a `requestToken` header manually.

## Security Model

For SDK-hosted SwiftUI views and sheets, do not expose clear PAN to the host app. The hosted card field keeps clear PAN in SDK-owned state for validation/submission, but the underlying UIKit text field, accessibility value, diagnostics, callbacks, and result models must not contain the full card number. CVV, ACH account, and ACH routing fields follow the same host-visible masking rule.

Do not generate public component initialization code with a custom `PayabliTransport`. The public `PayabliPayInPaymentFlow` initializers use SDK-owned transport; transport injection exists only for internal tests under `@testable import`.

Direct APIs are different: `addCard(_:)`, `capture(_:)`, and `authorize(_:)` accept card data supplied by the host app, so those flows are PCI-sensitive and cannot provide host-app PAN isolation. Recommend the hosted form when an integrator wants to avoid accessing clear PAN.

## Basic Store Flow

```swift
@StateObject private var paymentFlow = PayabliPayInPaymentFlow(
    entryPoint: entryPoint,
    environment: .sandbox,
    accessTokenProvider: {
        try await backend.fetchPayInAccessToken()
    },
    operation: .storePaymentMethod
)

PayabliPayInPaymentFlowView(
    component: paymentFlow,
    configuration: PayabliPayInPaymentFlowFormConfiguration(),
    onCompleted: { result in
        let storedMethod = result.storedPaymentMethod
    }
)
```

Direct API:

```swift
let stored = try await paymentFlow.addCard(PayabliPayInPaymentFlowCardData(
    cardNumber: "4111111111111111",
    expiration: "02/28",
    cardholderName: "Jane Doe",
    cvv: "123",
    billingZip: "33139"
))
```

## Basic Capture Flow

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
        source: "ios-sdk"
    )
)
```

Direct API:

```swift
let result = try await paymentFlow.capture(PayabliPayInPaymentFlowRequest(
    paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 1.00, serviceFee: 0.10),
    paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(data: cardData))
))
```

`serviceFee` and other currency fields are normalized as currency values, for example `0.10`.

Capture a prior authorization:

```swift
let result = try await paymentFlow.captureAuthorizedTransaction(
    PayabliPayInPaymentFlowAuthorizedRequest(
        transId: "authorized-transaction-id",
        paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 1.00)
    )
)
```

## Result

`PayabliPayInPaymentFlowResult` is unified:

- `kind == .storedPaymentMethod` and `storedPaymentMethod != nil` for stored-method submissions
- `kind == .transaction` and `transaction != nil` for capture/authorize
- `apiResponse` carries the full MoneyIn v2 response for transaction operations

## Form Configuration

`PayabliPayInPaymentFlowFormConfiguration` supports:

- card and ACH method selection for store/capture forms
- card-only method selection for authorize forms
- field ordering
- configurable sections
- visible label hiding
- per-field placeholders
- per-section vertical and horizontal input spacing
- per-field vertical spacing after a field
- required optional fields
- hidden values for ACH holder type, SEC code, device, method description, and customer data
- card-brand icon placement
- non-editable payment summary amount and fee rows

Section names are configurable:

```swift
PayabliPayInPaymentFlowFieldSection(
    title: "Customer Information",
    fields: [.firstName, .lastName, .billingEmail]
)
```

Placeholder-only inputs:

```swift
let fields: [PayabliPayInPaymentFlowField] = [.cardNumber, .cardExpiration, .cardCvv]

let config = PayabliPayInPaymentFlowFormConfiguration(
    labels: PayabliPayInPaymentFlowLabels(
        fieldPlaceholders: Dictionary(uniqueKeysWithValues: fields.map {
            ($0, PayabliPayInPaymentFlowLabels.defaultFieldLabels[$0] ?? $0.rawValue)
        })
    ),
    showsFieldLabels: false,
    hiddenFieldLabels: Set(fields)
)
```

The labels use `Postal Code` and `Billing Postal Code`.

## Payment Summary

Capture and authorize forms show read-only amount and fee rows before submit. Defaults:

- `Amount: $ 1.00`
- `Fee: $ 0.10`

The displayed label and value text can be overridden with `PayabliPayInPaymentFlowPaymentSummaryConfiguration`:

```swift
PayabliPayInPaymentFlowPaymentSummaryConfiguration(
    amountLabelText: "Amount:",
    amountValueText: "$ 1.00",
    feeLabelText: "Fee:",
    feeValueText: "$ 0.10"
)
```

Rows are vertical. Labels are left aligned and values are right aligned.

## Styling

Use `PayabliPayInPaymentFlowStyle` for visual styling:

```swift
PayabliPayInPaymentFlowStyle(
    accentColor: .blue,
    sectionTitle: PayabliPayInPaymentFlowTextStyle(font: .headline, color: .primary),
    input: PayabliPayInPaymentFlowInputStyle(
        font: .body,
        uiFont: UIFont.preferredFont(forTextStyle: .body),
        textColor: .primary,
        placeholderColor: Color(uiColor: .placeholderText),
        cornerRadius: 8
    ),
    layout: PayabliPayInPaymentFlowLayoutStyle(
        fieldGroupSpacing: 8,
        pairedFieldSpacing: 12,
        sectionSpacing: 18
    )
)
```

For custom fonts:

1. Add font files to the host app target.
2. Add them to `UIAppFonts` in the host app `Info.plist`.
3. Use `Font.custom(_:size:)` for SwiftUI-rendered text.
4. Use `UIFont(name:size:)` through `PayabliPayInPaymentFlowInputStyle.uiFont` for UIKit text fields.

## Accessibility

The component should remain fully accessible:

- keep minimum touch targets at or above `PayabliPayInPaymentFlowAccessibility.minimumTouchTarget`
- keep accessible labels even when visual labels are hidden
- never expose CVV, ACH account, account number, routing number, PAN, access tokens, or customer contact details in diagnostics, accessibility values, or host-visible UIKit text
- keep card brand icons decorative unless the field hint needs brand context
- preserve Dynamic Type and accessibility-size vertical stacking

Run:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPayInPaymentFlowTests
```

## File Map

- `PayabliPayInPaymentFlow.swift`: component facade and public operations
- `PayInPaymentFlowClient.swift`: MoneyIn v2 auth/capture HTTP client
- `PayInPaymentFlowTokenStorageClient.swift`: stored-method HTTP client
- `PayabliPayInPaymentFlowTypes.swift`: transaction request/response models
- `PayabliPayInPaymentFlowMethodModels.swift`: stored-method card/ACH models
- `PayabliPayInPaymentFlowFormConfiguration.swift`: form configuration, labels, sections, payment summary
- `PayabliPayInPaymentFlowSensitiveDataRedactor.swift`: PAN-pattern redaction for diagnostics and displayed errors
- `PayabliPayInPaymentFlowStyle.swift`: styling
- `PayabliPayInPaymentFlowView.swift`: SwiftUI form
- `PayabliPayInPaymentFlowViewModel.swift`: form state, validation, payload assembly
- `PayabliPayInPaymentFlowSheet.swift`: sheet modifier
- `PayabliPayInPaymentFlow+ObjC.swift`: Objective-C bridge for stored-method flows
- `PayabliPayInPaymentFlowDiagnostics.swift`: redacted diagnostics
- `Resources/PayabliBrandAssets.xcassets`: card brand images
