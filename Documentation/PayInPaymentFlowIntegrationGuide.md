# PayabliSDKPayInPaymentFlow Integration Guide

This guide shows how to integrate `PayabliSDKPayInPaymentFlow` in a native iOS
application, how to configure each operation, and how to customize the hosted
form.

For a complete field-level reference aimed at code generation, see
`Sources/PayabliSDKPayInPaymentFlow/LLM.md`.

## 1. Add The Product

Add the Swift package product to the host app target:

```swift
.product(name: "PayabliSDKPayInPaymentFlow", package: "sdk-ios")
```

Import it where the form or direct API is used:

```swift
import PayabliSDKPayInPaymentFlow
```

## 2. Provide A Mobile Access Token

The component expects an async token provider:

```swift
let accessTokenProvider: PayabliPayInPaymentFlowAccessTokenProvider = {
    try await backend.fetchPayInAccessToken()
}
```

Recommended production pattern:

1. The iOS app asks your backend for a short-lived Payabli mobile access token.
2. Your backend holds the private Payabli credentials.
3. The component calls `accessTokenProvider` just before network operations.

Do not embed Payabli `clientSecret` values in the app. Do not manually attach a
`requestToken` header for capture or authorize; these operations use the same
access-token provider model as token storage.

## 3. Choose Hosted UI Or Direct API

Use hosted UI when the app must avoid clear PAN access:

```swift
PayabliPayInPaymentFlowView(
    component: paymentFlow,
    configuration: configuration,
    style: style,
    onCompleted: { result in
        print(result.code)
    },
    onError: { error in
        print(error.localizedDescription)
    }
)
```

Use direct API only when the app is intentionally collecting raw card or bank
data:

```swift
let stored = try await paymentFlow.addCard(PayabliPayInPaymentFlowCardData(
    cardNumber: "4111111111111111",
    expiration: "02/28",
    cardholderName: "Jane Doe",
    cvv: "123",
    billingZip: "33139"
))
```

Direct card/ACH calls are PCI-sensitive because the host app supplies the data.

## 4. Store A Payment Method

Create a component for stored-method mode:

```swift
@MainActor
final class StorePaymentMethodViewModel: ObservableObject {
    @Published var isPresented = false

    let paymentFlow: PayabliPayInPaymentFlow

    init(backend: Backend) {
        paymentFlow = PayabliPayInPaymentFlow(
            entryPoint: backend.entryPoint,
            environment: .sandbox,
            accessTokenProvider: {
                try await backend.fetchPayInAccessToken()
            },
            operation: .storePaymentMethod
        )
    }
}
```

Render inline:

```swift
PayabliPayInPaymentFlowView(
    component: viewModel.paymentFlow,
    configuration: storeConfiguration,
    style: payabliStyle,
    onCompleted: { result in
        guard let stored = result.storedPaymentMethod else { return }
        print("Stored method:", stored.storedMethodId ?? "")
    }
)
```

Render as a sheet:

```swift
Button("Add Payment Method") {
    viewModel.isPresented = true
}
.payabliPayInPaymentFlowSheet(
    isPresented: $viewModel.isPresented,
    component: viewModel.paymentFlow,
    configuration: storeConfiguration,
    sheetConfiguration: PayabliPayInPaymentFlowSheetConfiguration(
        title: "Add Payment Method",
        subtitle: "Card or ACH",
        dismissButton: .close
    ),
    style: payabliStyle,
    onCompleted: { result in
        print(result.storedPaymentMethod?.storedMethodId ?? "")
    }
)
```

Direct stored card:

```swift
let storedCard = try await paymentFlow.addCard(
    PayabliPayInPaymentFlowCardData(
        cardNumber: "4111111111111111",
        expiration: "02/28",
        cardholderName: "Jane Doe",
        cvv: "123",
        billingZip: "33139"
    ),
    options: PayabliPayInPaymentFlowOptions(
        createAnonymous: false,
        forceCustomerCreation: true,
        customerData: PayabliPayInPaymentFlowCustomerData(
            firstName: "Jane",
            lastName: "Doe",
            billingEmail: "jane@example.com"
        ),
        source: "ios-sdk"
    )
)
```

Direct stored ACH:

```swift
let storedACH = try await paymentFlow.addACH(
    PayabliPayInPaymentFlowACHData(
        accountNumber: "111111111111",
        accountType: .checking,
        holderName: "Jane Doe",
        routingNumber: "123456780",
        secCode: .web,
        holderType: .personal
    ),
    options: PayabliPayInPaymentFlowOptions(
        achValidation: true,
        source: "ios-sdk"
    )
)
```

## 5. Capture A Transaction

Create a component in capture mode with request configuration:

```swift
let paymentFlow = PayabliPayInPaymentFlow(
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

Render the hosted form:

```swift
PayabliPayInPaymentFlowView(
    component: paymentFlow,
    configuration: captureConfiguration,
    style: payabliStyle,
    onCompleted: { result in
        print("Payment transaction:", result.transaction?.paymentTransId ?? "")
    }
)
```

The hosted capture form can collect card or ACH. The read-only payment summary
is displayed before the submit button and is derived from
`requestConfiguration.paymentDetails`.

Direct capture with card:

```swift
let cardData = PayabliPayInPaymentFlowCardData(
    cardNumber: "4111111111111111",
    expiration: "02/28",
    cardholderName: "Jane Doe",
    cvv: "123",
    billingZip: "33139"
)

let result = try await paymentFlow.capture(PayabliPayInPaymentFlowRequest(
    paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
        totalAmount: 1.00,
        serviceFee: 0.10,
        currency: "USD"
    ),
    paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(
        data: cardData,
        initiator: "payor",
        saveIfSuccess: false
    )),
    orderDescription: "iOS checkout",
    source: "ios-sdk"
))
```

Direct capture with a stored method:

```swift
let result = try await paymentFlow.capture(PayabliPayInPaymentFlowRequest(
    paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 25.00),
    paymentMethod: .stored(PayabliPayInPaymentFlowStoredMethod(
        method: .card,
        storedMethodId: "stored-method-id",
        storedMethodUsageType: .unscheduled,
        initiator: "payor"
    )),
    orderId: "ORDER-1001",
    source: "ios-sdk"
))
```

Direct capture also supports `.ach`, `.cloud`, `.check`, and `.cash`.

## 6. Authorize A Transaction

Create a component in authorize mode:

```swift
let paymentFlow = PayabliPayInPaymentFlow(
    entryPoint: entryPoint,
    environment: .sandbox,
    accessTokenProvider: {
        try await backend.fetchPayInAccessToken()
    },
    operation: .authorize,
    requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration(
        paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
            totalAmount: 1.00,
            serviceFee: 0.10,
            currency: "USD"
        ),
        orderDescription: "iOS authorization",
        source: "ios-sdk"
    )
)
```

Authorize supports card data only today. Do not configure ACH, stored methods,
cash, check, or cloud-device payment methods for authorization. Apple Pay can be
added later as a separate authorizable method.

Hosted authorize forms should use card-only configuration:

```swift
let authorizeConfiguration = PayabliPayInPaymentFlowFormConfiguration(
    allowedMethods: [.card],
    defaultMethod: .card
)
```

Direct authorize:

```swift
let result = try await paymentFlow.authorize(PayabliPayInPaymentFlowRequest(
    paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
        totalAmount: 1.00,
        serviceFee: 0.10,
        currency: "USD"
    ),
    paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(data: cardData)),
    orderDescription: "iOS authorization",
    source: "ios-sdk"
))
```

## 7. Capture A Prior Authorization

Capture an existing authorization by transaction ID:

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

`captureAuthorizedTransaction(_:)` is a direct API. It is not a hosted form
mode.

## 8. Complete Form Configuration Example

This configuration creates:

- placeholder-only card and customer inputs
- tight vertical spacing in `Card Information`
- separate `Customer Information` and `Payment Information` sections
- read-only amount and fee rows
- visible card brand icons
- hidden ACH SEC code and holder type defaults

```swift
let placeholderFields: [PayabliPayInPaymentFlowField] = [
    .cardholderName,
    .cardNumber,
    .cardExpiration,
    .cardCvv,
    .cardZip,
    .firstName,
    .lastName,
    .billingEmail,
    .billingZip
]

let labels = PayabliPayInPaymentFlowLabels(
    title: "Payment",
    subtitle: "Enter your payment details",
    submitButton: "Submit Payment",
    fieldLabels: PayabliPayInPaymentFlowLabels.defaultFieldLabels.merging([
        .cardZip: "Postal Code",
        .billingZip: "Billing Postal Code"
    ]) { _, new in new },
    fieldPlaceholders: Dictionary(uniqueKeysWithValues: placeholderFields.map {
        ($0, PayabliPayInPaymentFlowLabels.defaultFieldLabels[$0] ?? $0.rawValue)
    })
)

let configuration = PayabliPayInPaymentFlowFormConfiguration(
    allowedMethods: [.card, .ach],
    defaultMethod: .card,
    cardSections: [
        PayabliPayInPaymentFlowFieldSection(
            title: "Card Information",
            fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip],
            inputVerticalSpacing: 4,
            inputHorizontalSpacing: 8,
            fieldVerticalSpacings: [
                .cardNumber: 2,
                .cardExpiration: 2
            ]
        ),
        PayabliPayInPaymentFlowFieldSection(
            title: "Customer Information",
            fields: [.firstName, .lastName, .billingEmail, .billingZip],
            inputVerticalSpacing: 8
        ),
        PayabliPayInPaymentFlowFieldSection(
            title: "Payment Information",
            fields: [.amount, .serviceFee],
            inputVerticalSpacing: 6
        )
    ],
    achSections: [
        PayabliPayInPaymentFlowFieldSection(
            title: "Bank Information",
            fields: [.achHolder, .achRouting, .achAccount, .achAccountType],
            inputVerticalSpacing: 8,
            inputHorizontalSpacing: 8
        ),
        PayabliPayInPaymentFlowFieldSection(
            title: "Customer Information",
            fields: [.firstName, .lastName, .billingEmail, .billingZip]
        ),
        PayabliPayInPaymentFlowFieldSection(
            title: "Payment Information",
            fields: [.amount, .serviceFee]
        )
    ],
    hiddenValues: PayabliPayInPaymentFlowHiddenValues(
        achHolderType: .personal,
        achSecCode: .web,
        methodDescription: "iOS payment flow"
    ),
    options: PayabliPayInPaymentFlowOptions(
        createAnonymous: false,
        forceCustomerCreation: true,
        source: "ios-sdk"
    ),
    labels: labels,
    labelLayout: .placeholder,
    showsFieldLabels: false,
    hiddenFieldLabels: Set(placeholderFields),
    formatting: PayabliPayInPaymentFlowFormatting(
        insertsCardNumberSpaces: true,
        expirationSeparator: "/",
        masksACHAccountEntry: true
    ),
    inputSizing: PayabliPayInPaymentFlowInputSizing(
        defaultSize: PayabliPayInPaymentFlowInputSize(height: 52, horizontalPadding: 14),
        fieldSizes: [
            .cardCvv: PayabliPayInPaymentFlowInputSize(width: 120, height: 52)
        ]
    ),
    cardBrandIconPlacement: .trailing,
    errorMessagePlacement: .aboveSubmitButton,
    requiredFields: [.firstName, .lastName, .billingEmail],
    paymentSummary: PayabliPayInPaymentFlowPaymentSummaryConfiguration(
        amountLabelText: "Amount:",
        amountValueText: "$ 1.00",
        feeLabelText: "Fee:",
        feeValueText: "$ 0.10",
        rowSpacing: 6
    )
)
```

## 9. Configuration Field Reference

### `PayabliPayInPaymentFlowFormConfiguration`

| Field | Default | Description |
| --- | --- | --- |
| `allowedMethods` | `[.card, .ach]` | Methods available in the hosted method selector. |
| `defaultMethod` | `.card` | Initial selected method. If not allowed, the first allowed method is used. |
| `cardFieldOrder` | cardholder, number, expiration, CVV, postal code | Flat card order used when `cardSections` is nil. |
| `achFieldOrder` | holder, routing, account, account type, holder type | Flat ACH order used when `achSections` is nil. |
| `cardSections` | nil | Custom card sections. Required and payment summary fields are appended if missing. |
| `achSections` | nil | Custom ACH sections. `achSecCode` is not rendered. Required and payment summary fields are appended if missing. |
| `hiddenValues` | default hidden values | Non-editable values submitted with the hosted form. |
| `options` | empty options | Token-storage options for hosted `.storePaymentMethod`. |
| `labels` | default labels | Title, subtitle, submit text, labels, placeholders. |
| `labelLayout` | `.external` | `.external` for visible labels, `.placeholder` for placeholder-first UI. |
| `showsFieldLabels` | nil | Optional global visible-label override. Nil follows `labelLayout`. |
| `hiddenFieldLabels` | `[]` | Hide visible labels for specific fields. Accessibility labels remain. |
| `formatting` | default formatting | Card spacing, expiration separator, ACH account masking. |
| `inputSizing` | default input sizing | Default and per-field input sizes. |
| `cardBrandIconPlacement` | `.trailing` | `.leading`, `.trailing`, or `.hidden`. |
| `errorMessagePlacement` | `.aboveSubmitButton` | `.top` or `.aboveSubmitButton`. |
| `requiredFields` | `[]` | Optional visible fields to require. Amount is always required. |
| `paymentSummary` | default summary | Read-only amount and fee text/styles. |

### `PayabliPayInPaymentFlowFieldSection`

| Field | Description |
| --- | --- |
| `id` | Optional stable identifier. Defaults to title or joined field names. |
| `title` | Optional section title. This is how section names are configured. |
| `titleStyle` | Optional style override for that section title. |
| `fields` | Ordered fields in the section. |
| `inputVerticalSpacing` | Section-level vertical spacing between inputs. |
| `inputHorizontalSpacing` | Section-level horizontal spacing for paired inputs. |
| `fieldVerticalSpacings` | Per-field vertical spacing after specific fields. |

### `PayabliPayInPaymentFlowLabels`

| Field | Default | Description |
| --- | --- | --- |
| `title` | `Save Payment Method` | Form header title. |
| `subtitle` | nil | Optional form header subtitle. |
| `submitButton` | `Add Payment Method` | Submit button label. |
| `fieldLabels` | default labels | Visible and accessibility labels by field. |
| `fieldPlaceholders` | empty | Placeholder text by field. |

Default field labels:

| Field | Label |
| --- | --- |
| `.cardholderName` | Name on card |
| `.cardNumber` | Card number |
| `.cardExpiration` | Expiration |
| `.cardCvv` | CVV |
| `.cardZip` | Postal Code |
| `.achHolder` | Account holder |
| `.achRouting` | Routing number |
| `.achAccount` | Account number |
| `.achAccountType` | Account type |
| `.achHolderType` | Holder type |
| `.achSecCode` | SEC code |
| `.achDevice` | Device |
| `.methodDescription` | Description |
| `.firstName` | First name |
| `.lastName` | Last name |
| `.customerNumber` | Customer number |
| `.billingEmail` | Billing email |
| `.billingZip` | Billing Postal Code |
| `.amount` | Amount |
| `.serviceFee` | Fee |

### `PayabliPayInPaymentFlowHiddenValues`

| Field | Default | Description |
| --- | --- | --- |
| `achHolderType` | nil | ACH holder type submitted without rendering the field. |
| `achSecCode` | `.web` | ACH SEC code submitted without rendering the field. |
| `achDevice` | nil | ACH device value submitted without rendering the field. |
| `methodDescription` | nil | Stored-method description submitted without rendering the field. |
| `customerData` | nil | Default customer data merged with visible customer fields. |

### `PayabliPayInPaymentFlowFormatting`

| Field | Default | Description |
| --- | --- | --- |
| `insertsCardNumberSpaces` | true | Adds visual card number grouping. |
| `expirationSeparator` | `/` | Expiration separator. Empty resolves to `/`. |
| `masksACHAccountEntry` | true | Masks ACH account input. |

### `PayabliPayInPaymentFlowInputSizing`

| Field | Description |
| --- | --- |
| `defaultSize` | Default `PayabliPayInPaymentFlowInputSize`. |
| `fieldSizes` | Per-field size overrides. |

`PayabliPayInPaymentFlowInputSize` fields:

| Field | Default | Description |
| --- | --- | --- |
| `width` | nil | Optional fixed width. |
| `height` | 52 | Input height, clamped to the minimum touch target. |
| `horizontalPadding` | 14 | Text padding inside the input. |

### `PayabliPayInPaymentFlowPaymentSummaryConfiguration`

| Field | Default | Description |
| --- | --- | --- |
| `amountLabelText` | derived from label | Override amount label. |
| `amountValueText` | derived from amount | Override amount value. |
| `feeLabelText` | derived from label | Override fee label. |
| `feeValueText` | derived from fee | Override fee value. |
| `currencySymbol` | `$` | Symbol for generated value text. |
| `labelStyle` | subheadline secondary | Label font/color. |
| `valueStyle` | semibold subheadline primary | Value font/color. |
| `rowSpacing` | 8 | Vertical spacing between rows. |

## 10. Styling Reference

```swift
let payabliStyle = PayabliPayInPaymentFlowStyle(
    accentColor: .blue,
    title: PayabliPayInPaymentFlowTextStyle(
        font: .title3.weight(.semibold),
        color: .primary
    ),
    subtitle: PayabliPayInPaymentFlowTextStyle(
        font: .subheadline,
        color: .secondary
    ),
    sectionTitle: PayabliPayInPaymentFlowTextStyle(
        font: .subheadline.weight(.semibold),
        color: .primary
    ),
    label: PayabliPayInPaymentFlowTextStyle(
        font: .footnote.weight(.medium),
        color: Color(uiColor: .secondaryLabel)
    ),
    input: PayabliPayInPaymentFlowInputStyle(
        font: .body,
        uiFont: UIFont(name: "Inter-Regular", size: 16),
        textColor: .primary,
        placeholderColor: Color(uiColor: .placeholderText),
        backgroundColor: Color(uiColor: .secondarySystemBackground),
        focusedBackgroundColor: Color(uiColor: .systemBackground),
        borderColor: Color(uiColor: .separator).opacity(0.45),
        focusedBorderColor: .blue,
        borderWidth: 1,
        focusedBorderWidth: 1.5,
        cornerRadius: 8,
        pickerIconColor: .secondary
    ),
    submitButton: PayabliPayInPaymentFlowSubmitButtonStyle(
        font: .body.weight(.semibold),
        backgroundColor: .blue,
        foregroundColor: .white,
        disabledBackgroundColor: Color(uiColor: .systemGray5),
        disabledForegroundColor: Color(uiColor: .secondaryLabel),
        cornerRadius: 8,
        height: 52,
        horizontalPadding: 16
    ),
    error: PayabliPayInPaymentFlowTextStyle(
        font: .footnote,
        color: .red
    ),
    layout: PayabliPayInPaymentFlowLayoutStyle(
        contentSpacing: 20,
        headerSpacing: 4,
        fieldGroupSpacing: 12,
        pairedFieldSpacing: 12,
        labelSpacing: 7,
        sectionSpacing: 18,
        sectionTitleSpacing: 10
    )
)
```

Style fields:

| Type | Fields |
| --- | --- |
| `PayabliPayInPaymentFlowTextStyle` | `font`, `color` |
| `PayabliPayInPaymentFlowStyle` | `accentColor`, `title`, `subtitle`, `sectionTitle`, `label`, `input`, `submitButton`, `error`, `layout` |
| `PayabliPayInPaymentFlowInputStyle` | `font`, `uiFont`, `textColor`, `placeholderColor`, `backgroundColor`, `focusedBackgroundColor`, `borderColor`, `focusedBorderColor`, `borderWidth`, `focusedBorderWidth`, `cornerRadius`, `pickerIconColor` |
| `PayabliPayInPaymentFlowSubmitButtonStyle` | `font`, `backgroundColor`, `foregroundColor`, `disabledBackgroundColor`, `disabledForegroundColor`, `cornerRadius`, `height`, `horizontalPadding` |
| `PayabliPayInPaymentFlowLayoutStyle` | `contentSpacing`, `headerSpacing`, `fieldGroupSpacing`, `pairedFieldSpacing`, `labelSpacing`, `sectionSpacing`, `sectionTitleSpacing`, `inputVerticalSpacing`, `inputHorizontalSpacing` |

Apply style inline:

```swift
PayabliPayInPaymentFlowView(
    component: paymentFlow,
    configuration: configuration,
    style: payabliStyle,
    onCompleted: { _ in }
)
```

Apply style through environment:

```swift
PayabliPayInPaymentFlowView(
    component: paymentFlow,
    configuration: configuration,
    onCompleted: { _ in }
)
.payabliPayInPaymentFlowStyle(payabliStyle)
```

### Custom Fonts

The SDK can use any font available to the host app.

1. Add `.ttf` or `.otf` files to the app target.
2. Add the filenames to `UIAppFonts` in `Info.plist`.
3. Use `Font.custom(_:size:)` for SwiftUI text styles.
4. Use `UIFont(name:size:)` in `PayabliPayInPaymentFlowInputStyle.uiFont` for
   UIKit-backed input fields.

Example:

```swift
let style = PayabliPayInPaymentFlowStyle(
    title: PayabliPayInPaymentFlowTextStyle(
        font: .custom("Inter-SemiBold", size: 20),
        color: .primary
    ),
    input: PayabliPayInPaymentFlowInputStyle(
        font: .custom("Inter-Regular", size: 16),
        uiFont: UIFont(name: "Inter-Regular", size: 16)
    )
)
```

If `UIFont(name:size:)` returns nil, verify the font's PostScript name and
`UIAppFonts` entry.

## 11. Sheet Configuration Reference

```swift
let sheetConfiguration = PayabliPayInPaymentFlowSheetConfiguration(
    title: "Payment",
    subtitle: "Review and submit",
    dismissButton: .close,
    dismissesOnSuccess: true,
    detents: [.medium, .large],
    dragIndicatorVisibility: .visible,
    contentInsets: EdgeInsets(top: 20, leading: 20, bottom: 24, trailing: 20),
    movesFormHeaderToSheetHeader: true,
    sizesToContentWhenPossible: true,
    expandsToLargeWhenContentDoesNotFit: true
)
```

| Field | Description |
| --- | --- |
| `title` | Sheet title. If nil and `movesFormHeaderToSheetHeader` is true, the form title is used. |
| `subtitle` | Sheet subtitle. If nil and `movesFormHeaderToSheetHeader` is true, the form subtitle is used. |
| `dismissButton` | `.close`, `.back`, or `.hidden`. |
| `dismissesOnSuccess` | Dismiss the sheet after successful completion. |
| `detents` | SwiftUI presentation detents. Empty set resolves to `.large`. |
| `dragIndicatorVisibility` | SwiftUI drag indicator visibility. |
| `contentInsets` | Sheet content padding. |
| `movesFormHeaderToSheetHeader` | Moves form title/subtitle into the sheet header. |
| `sizesToContentWhenPossible` | Uses content-sized sheet behavior when possible. |
| `expandsToLargeWhenContentDoesNotFit` | Expands when smaller detents cannot fit content. |

## 12. Request Configuration Reference

### `PayabliPayInPaymentFlowPaymentDetails`

| Field | Description |
| --- | --- |
| `totalAmount` | Required amount. Must be greater than 0. |
| `serviceFee` | Optional service fee. Must not be negative. Serialized as currency, for example `0.10`. |
| `currency` | Optional currency, for example `USD`. |
| `checkNumber` | Optional check number for check workflows. |
| `checkUniqueId` | Optional check unique ID for check workflows. |

### `PayabliPayInPaymentFlowRequestConfiguration`

| Field | Description |
| --- | --- |
| `paymentDetails` | Required payment details used by hosted capture/authorize. |
| `accountId` | Optional account identifier. |
| `customerData` | Customer defaults merged with form-entered customer data. |
| `ipAddress` | Optional IP address. |
| `orderDescription` | Optional order description. |
| `orderId` | Optional order ID. |
| `source` | Optional source string. |
| `subdomain` | Optional subdomain. |
| `subscriptionId` | Optional subscription ID. |
| `idempotencyKey` | Optional idempotency key. |
| `achValidation` | Optional ACH validation flag. |
| `forceCustomerCreation` | Optional customer-creation flag. |
| `validation` | Client-side validation options. |

### `PayabliPayInPaymentFlowCustomerData`

Fields:

- `additionalData`
- `billingAddress1`
- `billingAddress2`
- `billingCity`
- `billingCountry`
- `billingEmail`
- `billingPhone`
- `billingState`
- `billingZip`
- `company`
- `customerId`
- `customerNumber`
- `firstName`
- `identifierFields`
- `lastName`
- `shippingAddress1`
- `shippingAddress2`
- `shippingCity`
- `shippingCountry`
- `shippingState`
- `shippingZip`

### `PayabliPayInPaymentFlowValidation`

| Field | Default | Description |
| --- | --- | --- |
| `requiresLuhnCheck` | true | Runs client-side Luhn validation for cards. |
| `validatesACHRoutingChecksum` | true | Runs client-side ACH routing checksum validation. |

## 13. Result Handling

```swift
func handle(_ result: PayabliPayInPaymentFlowResult) {
    switch result.kind {
    case .storedPaymentMethod:
        let stored = result.storedPaymentMethod
        print(stored?.storedMethodId ?? "")

    case .transaction:
        let transaction = result.transaction
        print(transaction?.paymentTransId ?? "")
    }
}
```

`PayabliPayInPaymentFlowResult` fields:

- `kind`
- `code`
- `reason`
- `explanation`
- `action`
- `transaction`
- `storedPaymentMethod`
- `apiResponse`

Stored-method fields:

- `storedMethodId`
- `methodReferenceId`
- `resultCode`
- `resultText`
- `customerId`
- `responseText`
- `apiResponse`

Transaction fields include:

- `paymentTransId`
- `gatewayTransId`
- `orderId`
- `method`
- `transStatus`
- `paypointId`
- `totalAmount`
- `netAmount`
- `feeAmount`
- `settlementStatus`
- `operation`
- `responseData`
- `source`
- `isValidatedACH`
- `transactionTime`
- `achSecCode`
- `achHolderType`
- `ipAddress`
- `walletType`

## 14. Diagnostics

Diagnostics are disabled by default:

```swift
let paymentFlow = PayabliPayInPaymentFlow(
    entryPoint: entryPoint,
    environment: .sandbox,
    accessTokenProvider: accessTokenProvider,
    diagnostics: .disabled
)
```

Enable diagnostics for QA:

```swift
let diagnostics = PayabliPayInPaymentFlowDiagnostics.enabled { entry in
    print("[PayIn]", entry.phase.rawValue, entry.method, entry.url)
    if let body = entry.body {
        print(body)
    }
}
```

Diagnostic entries include:

- `phase`
- `timestamp`
- `method`
- `url`
- `statusCode`
- `headers`
- `body`
- `durationMilliseconds`
- `errorDescription`

The SDK redacts sensitive fields, including authorization headers, request
tokens, access tokens, client secrets, card number, CVV, ACH account, ACH
routing, stored method IDs, customer IDs, names, emails, phones, and addresses.

## 15. Accessibility Checklist

When customizing:

- Keep input and submit heights at or above the SDK minimum touch target.
- If visual labels are hidden, keep `fieldLabels` meaningful for accessibility.
- Do not put clear PAN, CVV, ACH account, routing number, tokens, or customer
  contact values in custom labels, placeholders, diagnostics, or result UI.
- Keep section titles concise and meaningful.
- Test Dynamic Type, especially accessibility sizes.
- Ensure custom colors have sufficient contrast.

## 16. Bridge Scope

Flutter, React Native, and .NET MAUI bridges currently expose stored card/ACH
payment-method creation. Native Swift integrations should call
`PayabliSDKPayInPaymentFlow` directly for capture, authorize, and
capture-authorized transaction flows until those request models are added to the
bridge APIs.

The React Native Expo QA app is under `Example/PayabliReactNativeDemo`.

## 17. Testing

Run component tests:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPayInPaymentFlowTests
```

Run coverage:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPayInPaymentFlowTests \
  -enableCodeCoverage YES \
  -resultBundlePath build/TestResults/PayInPaymentFlowCoverage.xcresult

xcrun xccov view --report build/TestResults/PayInPaymentFlowCoverage.xcresult
```

Run the native sample app:

```bash
xcodebuild build -project Example/PayabliDemo/PayabliDemo.xcodeproj \
  -scheme PayabliDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1'
```

Run the React Native example type check:

```bash
cd Example/PayabliReactNativeDemo
npm run typecheck
```
