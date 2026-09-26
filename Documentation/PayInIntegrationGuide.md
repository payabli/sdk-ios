# PayabliSDKPayIn Integration Guide

This guide shows how to integrate `PayabliSDKPayIn` in a native iOS
application, how to configure each operation, and how to customize the hosted
form.

For a complete field-level reference aimed at code generation, see
`Sources/PayabliSDKPayIn/LLM.md`.

## 1. Add The Product

Add the Swift package product to the host app target:

```swift
.product(name: "PayabliSDKPayIn", package: "sdk-ios")
```

Import it where the form or direct API is used:

```swift
import PayabliSDKCore
import PayabliSDKPayIn
```

## 2. Provide A Mobile Access Token

The session expects an async token provider:

```swift
let config = try PayabliConfig(
    entryPoint: entryPoint,
    environment: .sandbox,
    tokenProvider: { try await backend.fetchPayInAccessToken() }
)
```

Recommended production pattern:

1. The iOS app asks your backend for a short-lived Payabli mobile access token.
2. Your backend holds the private Payabli credentials.
3. The session calls `tokenProvider` before its first request and again whenever a token is
   rejected, and holds the result in memory in between.

Do not embed Payabli `clientSecret` values in the app. Do not manually attach a
`requestToken` header for capture or authorize; these operations use the same
access-token provider model as token storage.

## 3. Choose Hosted UI Or Direct API

Use hosted UI when the app must avoid clear PAN access:

```swift
PayabliPayInView(
    component: paymentFlow,
    configuration: configuration,
    style: style,
    onCompleted: { result in
        outcome = result.code
    },
    onError: { error in
        // Show this: it names what the service rejected. Do not log it. The
        // description carries the service's own wording, which can quote what was
        // submitted; log `(error as? any PayabliError)?.code` instead.
        message = error.localizedDescription
    }
)
```

Use direct API only when the app is intentionally collecting raw card or bank
data:

```swift
let stored = try await paymentFlow.addCard(PayabliPayInCardData(
    cardNumber: "4111111111111111",
    expiration: "02/28",
    cardholderName: "Jane Doe",
    cvv: "123",
    billingZip: "33139"
))
```

Direct card/bank account calls are PCI-sensitive because the host app supplies the data.

## 4. Store A Payment Method

Create a component for stored-method mode:

```swift
@MainActor
final class StorePaymentMethodViewModel: ObservableObject {
    @Published var isPresented = false

    let paymentFlow: PayabliPayIn

    // The session is built by the caller, which is where a rejected configuration can be handled.
    init(session: PayabliSession) {
        paymentFlow = PayabliPayIn(
            session: session,
            operation: .storePaymentMethod
        )
    }
}
```

Render inline:

```swift
PayabliPayInView(
    component: viewModel.paymentFlow,
    configuration: storeConfiguration,
    style: payabliStyle,
    onCompleted: { result in
        guard let stored = result.storedPaymentMethod else { return }
        // A stored-method id is a token: keep it, do not log it.
        storedMethodId = stored.storedMethodId
        storedMethodType = stored.method
    }
)
```

Render as a sheet:

```swift
Button("Add Payment Method") {
    viewModel.isPresented = true
}
.payabliPayInSheet(
    isPresented: $viewModel.isPresented,
    component: viewModel.paymentFlow,
    configuration: storeConfiguration,
    sheetConfiguration: PayabliPayInSheetConfiguration(
        title: "Add Payment Method",
        subtitle: "Card or bank account",
        dismissButton: .close
    ),
    style: payabliStyle,
    onCompleted: { result in
        // A stored-method id is a token: keep it, do not log it.
        storedMethodId = result.storedPaymentMethod?.storedMethodId
        storedMethodType = result.storedPaymentMethod?.method
    }
)
```

Direct stored card:

```swift
let storedCard = try await paymentFlow.addCard(
    PayabliPayInCardData(
        cardNumber: "4111111111111111",
        expiration: "02/28",
        cardholderName: "Jane Doe",
        cvv: "123",
        billingZip: "33139"
    ),
    options: PayabliPayInOptions(
        createAnonymous: false,
        forceCustomerCreation: true,
        customerData: PayabliPayInCustomerData(
            firstName: "Jane",
            lastName: "Doe",
            billingEmail: "jane@example.com"
        ),
        source: "ios-sdk"
    )
)
```

Direct stored bank account:

```swift
let storedBankAccount = try await paymentFlow.addBankAccount(
    PayabliPayInBankAccountData(
        accountNumber: "111111111111",
        accountType: .checking,
        holderName: "Jane Doe",
        routingNumber: "123456780",
        secCode: .web,
        holderType: .personal
    ),
    options: PayabliPayInOptions(
        achValidation: true,
        source: "ios-sdk"
    )
)
```

## 5. Capture A Transaction

Create a component in capture mode with request configuration:

```swift
let paymentFlow = PayabliPayIn(
    session: PayabliSession(config: try PayabliConfig(
        entryPoint: entryPoint,
        environment: .sandbox,
        tokenProvider: { try await backend.fetchPayInAccessToken() }
    )),
    operation: .capture,
    requestConfiguration: PayabliPayInRequestConfiguration(
        paymentDetails: PayabliPayInPaymentDetails(
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
PayabliPayInView(
    component: paymentFlow,
    configuration: captureConfiguration,
    style: payabliStyle,
    onCompleted: { result in
        print("Payment transaction:", result.transaction?.paymentTransId ?? "")
    }
)
```

The hosted capture form can collect card or bank account. The read-only payment summary
is displayed before the submit button and is derived from
`requestConfiguration.paymentDetails`.

Direct capture with card:

```swift
let cardData = PayabliPayInCardData(
    cardNumber: "4111111111111111",
    expiration: "02/28",
    cardholderName: "Jane Doe",
    cvv: "123",
    billingZip: "33139"
)

let result = try await paymentFlow.capture(PayabliPayInRequest(
    paymentDetails: PayabliPayInPaymentDetails(
        totalAmount: 1.00,
        serviceFee: 0.10,
        currency: "USD"
    ),
    paymentMethod: .card(PayabliPayInPaymentMethod.Card(
        data: cardData,
        initiator: "payor",
        saveIfSuccess: false
    )),
    orderDescription: "iOS checkout",
    source: "ios-sdk"
))
```

Direct capture with a stored method, charged as the method and identifier the store returned:

```swift
let stored = try await paymentFlow.addCard(cardData)
guard let storedMethodId = stored.storedMethodId else { return }

let result = try await paymentFlow.capture(PayabliPayInRequest(
    paymentDetails: PayabliPayInPaymentDetails(totalAmount: 25.00),
    paymentMethod: .stored(PayabliPayInPaymentMethod.Stored(
        method: stored.method,
        storedMethodId: storedMethodId
    )),
    orderId: "ORDER-1001",
    source: "ios-sdk"
))
```

Direct capture also supports `.bankAccount`, `.cloudDevice`, `.check`, and `.cash`.

## 6. Authorize A Transaction

Create a component in authorize mode:

```swift
let paymentFlow = PayabliPayIn(
    session: PayabliSession(config: try PayabliConfig(
        entryPoint: entryPoint,
        environment: .sandbox,
        tokenProvider: { try await backend.fetchPayInAccessToken() }
    )),
    operation: .authorize,
    requestConfiguration: PayabliPayInRequestConfiguration(
        paymentDetails: PayabliPayInPaymentDetails(
            totalAmount: 1.00,
            serviceFee: 0.10,
            currency: "USD"
        ),
        orderDescription: "iOS authorization",
        source: "ios-sdk"
    )
)
```

The direct `authorize(_:)` API accepts a card, a stored card, or a cloud device,
and refuses any other payment method before anything is sent. The hosted
authorize form collects a card only.

Hosted authorize forms should use card-only configuration:

```swift
let authorizeConfiguration = PayabliPayInFormConfiguration(
    allowedMethods: [.card],
    defaultMethod: .card
)
```

Direct authorize:

```swift
let result = try await paymentFlow.authorize(PayabliPayInRequest(
    paymentDetails: PayabliPayInPaymentDetails(
        totalAmount: 1.00,
        serviceFee: 0.10,
        currency: "USD"
    ),
    paymentMethod: .card(PayabliPayInPaymentMethod.Card(data: cardData)),
    orderDescription: "iOS authorization",
    source: "ios-sdk"
))
```

## 7. Capture A Prior Authorization

Capture an existing authorization by transaction ID:

```swift
let result = try await paymentFlow.captureAuthorizedTransaction(
    PayabliPayInAuthorizedRequest(
        transId: "authorized-transaction-id",
        paymentDetails: PayabliPayInPaymentDetails(
            totalAmount: 1.00,
            serviceFee: 0.10,
            currency: "USD"
        )
    )
)
```

`captureAuthorizedTransaction(_:)` is a direct API. It is not a hosted form
mode.

## 8. Reverse A Transaction

Release an authorization's hold, or undo a capture that has not settled:

```swift
let result = try await paymentFlow.voidTransaction("authorized-transaction-id")
```

`voidTransaction(_:)` is a direct API. It takes the transaction and nothing else,
because the route carries the identifier in its path and there is no partial void.

The result is returned and not published. `lastResult` keeps whatever the last
submission left there, so read the returned value rather than waiting on the
published one: a screen showing what a payment did does not start showing what was
done to it afterwards.

Which transactions can still be reversed is the service's to decide, and the SDK
mirrors no rule of its own. A state it will not reverse arrives as
`PayabliPayInError.transactionFailed`, carrying the service's own
reason. A reversal answers `A0003` and calls itself canceled, where a capture
answers `A0000`, so read the code rather than comparing against one literal.

## 9. Complete Form Configuration Example

This configuration creates:

- placeholder-only card and customer inputs
- tight vertical spacing in `Card Information`
- separate `Customer Information` and `Payment Information` sections
- read-only amount and fee rows
- visible card brand icons
- hidden SEC code and holder type defaults

```swift
let placeholderFields: [PayabliPayInField] = [
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

let labels = PayabliPayInLabels(
    title: "Payment",
    subtitle: "Enter your payment details",
    submitButton: "Submit Payment",
    fieldLabels: PayabliPayInLabels.defaultFieldLabels.merging([
        .cardZip: "Postal Code",
        .billingZip: "Billing Postal Code"
    ]) { _, new in new },
    fieldPlaceholders: Dictionary(uniqueKeysWithValues: placeholderFields.map {
        ($0, PayabliPayInLabels.defaultFieldLabels[$0] ?? $0.rawValue)
    })
)

let configuration = PayabliPayInFormConfiguration(
    allowedMethods: [.card, .bankAccount],
    defaultMethod: .card,
    cardSections: [
        PayabliPayInFieldSection(
            title: "Card Information",
            fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip],
            inputVerticalSpacing: 4,
            inputHorizontalSpacing: 8,
            fieldVerticalSpacings: [
                .cardNumber: 2,
                .cardExpiration: 2
            ]
        ),
        PayabliPayInFieldSection(
            title: "Customer Information",
            fields: [.firstName, .lastName, .billingEmail, .billingZip],
            inputVerticalSpacing: 8
        ),
        PayabliPayInFieldSection(
            title: "Payment Information",
            fields: [.amount, .serviceFee],
            inputVerticalSpacing: 6
        )
    ],
    bankSections: [
        PayabliPayInFieldSection(
            title: "Bank Information",
            fields: [.accountHolder, .routingNumber, .accountNumber, .accountType],
            inputVerticalSpacing: 8,
            inputHorizontalSpacing: 8
        ),
        PayabliPayInFieldSection(
            title: "Customer Information",
            fields: [.firstName, .lastName, .billingEmail, .billingZip]
        ),
        PayabliPayInFieldSection(
            title: "Payment Information",
            fields: [.amount, .serviceFee]
        )
    ],
    hiddenValues: PayabliPayInHiddenValues(
        accountHolderType: .personal,
        secCode: .web,
        methodDescription: "iOS payment flow"
    ),
    options: PayabliPayInOptions(
        createAnonymous: false,
        forceCustomerCreation: true,
        source: "ios-sdk"
    ),
    labels: labels,
    labelLayout: .placeholder,
    showsFieldLabels: false,
    hiddenFieldLabels: Set(placeholderFields),
    formatting: PayabliPayInFormatting(
        insertsCardNumberSpaces: true,
        expirationSeparator: "/",
        masksAccountNumber: true
    ),
    inputSizing: PayabliPayInInputSizing(
        defaultSize: PayabliPayInInputSize(height: 52, horizontalPadding: 14),
        fieldSizes: [
            .cardCvv: PayabliPayInInputSize(width: 120, height: 52)
        ]
    ),
    cardBrandIconPlacement: .trailing,
    errorMessagePlacement: .aboveSubmitButton,
    requiredFields: [.firstName, .lastName, .billingEmail],
    paymentSummary: PayabliPayInPaymentSummaryConfiguration(
        amountLabelText: "Amount:",
        amountValueText: "$ 1.00",
        feeLabelText: "Fee:",
        feeValueText: "$ 0.10",
        rowSpacing: 6
    )
)
```

## 10. Configuration Field Reference

### `PayabliPayInFormConfiguration`

| Field | Default | Description |
| --- | --- | --- |
| `allowedMethods` | `[.card, .bankAccount]` | Methods available in the hosted method selector. |
| `defaultMethod` | `.card` | Initial selected method. If not allowed, the first allowed method is used. |
| `cardFieldOrder` | cardholder, number, expiration, CVV, postal code | Flat card order used when `cardSections` is nil. |
| `bankFieldOrder` | holder, routing, account, account type, holder type | Flat bank account order used when `bankSections` is nil. |
| `cardSections` | nil | Custom card sections. Required and payment summary fields are appended if missing. |
| `bankSections` | nil | Custom bank account sections. `secCode` is not rendered. Required and payment summary fields are appended if missing. |
| `hiddenValues` | default hidden values | Non-editable values submitted with the hosted form. |
| `options` | empty options | Token-storage options for hosted `.storePaymentMethod`. |
| `labels` | default labels | Title, subtitle, submit text, labels, placeholders. |
| `labelLayout` | `.external` | `.external` for visible labels, `.placeholder` for placeholder-first UI. |
| `showsFieldLabels` | nil | Optional global visible-label override. Nil follows `labelLayout`. |
| `hiddenFieldLabels` | `[]` | Hide visible labels for specific fields. Accessibility labels remain. |
| `formatting` | default formatting | Card spacing, expiration separator, account number masking. |
| `inputSizing` | default input sizing | Default and per-field input sizes. |
| `cardBrandIconPlacement` | `.trailing` | `.leading`, `.trailing`, or `.hidden`. |
| `errorMessagePlacement` | `.aboveSubmitButton` | `.top` or `.aboveSubmitButton`. |
| `requiredFields` | `[]` | Optional visible fields to require. Amount is always required. |
| `paymentSummary` | default summary | Read-only amount and fee text/styles. |

### `PayabliPayInFieldSection`

| Field | Description |
| --- | --- |
| `id` | Optional stable identifier. Defaults to title or joined field names. |
| `title` | Optional section title. This is how section names are configured. |
| `titleStyle` | Optional style override for that section title. |
| `fields` | Ordered fields in the section. |
| `inputVerticalSpacing` | Section-level vertical spacing between inputs. |
| `inputHorizontalSpacing` | Section-level horizontal spacing for paired inputs. |
| `fieldVerticalSpacings` | Per-field vertical spacing after specific fields. |

### `PayabliPayInLabels`

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
| `.accountHolder` | Account holder |
| `.routingNumber` | Routing number |
| `.accountNumber` | Account number |
| `.accountType` | Account type |
| `.accountHolderType` | Holder type |
| `.secCode` | SEC code |
| `.deviceId` | Device |
| `.methodDescription` | Description |
| `.firstName` | First name |
| `.lastName` | Last name |
| `.customerNumber` | Customer number |
| `.billingEmail` | Billing email |
| `.billingZip` | Billing Postal Code |
| `.amount` | Amount |
| `.serviceFee` | Fee |

### `PayabliPayInHiddenValues`

| Field | Default | Description |
| --- | --- | --- |
| `accountHolderType` | nil | account holder type submitted without rendering the field. |
| `secCode` | `.web` | SEC code submitted without rendering the field. |
| `deviceId` | nil | device ID submitted without rendering the field. |
| `methodDescription` | nil | Stored-method description submitted without rendering the field. |
| `customerData` | nil | Default customer data merged with visible customer fields. |

### `PayabliPayInFormatting`

| Field | Default | Description |
| --- | --- | --- |
| `insertsCardNumberSpaces` | true | Adds visual card number grouping. |
| `expirationSeparator` | `/` | Expiration separator. Empty resolves to `/`. |
| `masksAccountNumber` | true | Masks account number input. |

### `PayabliPayInInputSizing`

| Field | Description |
| --- | --- |
| `defaultSize` | Default `PayabliPayInInputSize`. |
| `fieldSizes` | Per-field size overrides. |

`PayabliPayInInputSize` fields:

| Field | Default | Description |
| --- | --- | --- |
| `width` | nil | Optional fixed width. |
| `height` | 52 | Input height, clamped to the minimum touch target. |
| `horizontalPadding` | 14 | Text padding inside the input. |

### `PayabliPayInPaymentSummaryConfiguration`

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

## 11. Styling Reference

```swift
let payabliStyle = PayabliPayInStyle(
    accentColor: .blue,
    title: PayabliPayInTextStyle(
        font: .title3.weight(.semibold),
        color: .primary
    ),
    subtitle: PayabliPayInTextStyle(
        font: .subheadline,
        color: .secondary
    ),
    sectionTitle: PayabliPayInTextStyle(
        font: .subheadline.weight(.semibold),
        color: .primary
    ),
    label: PayabliPayInTextStyle(
        font: .footnote.weight(.medium),
        color: Color(uiColor: .secondaryLabel)
    ),
    input: PayabliPayInInputStyle(
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
    submitButton: PayabliPayInSubmitButtonStyle(
        font: .body.weight(.semibold),
        backgroundColor: .blue,
        foregroundColor: .white,
        disabledBackgroundColor: Color(uiColor: .systemGray5),
        disabledForegroundColor: Color(uiColor: .secondaryLabel),
        cornerRadius: 8,
        height: 52,
        horizontalPadding: 16
    ),
    error: PayabliPayInTextStyle(
        font: .footnote,
        color: .red
    ),
    layout: PayabliPayInLayoutStyle(
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
| `PayabliPayInTextStyle` | `font`, `color` |
| `PayabliPayInStyle` | `accentColor`, `title`, `subtitle`, `sectionTitle`, `label`, `input`, `submitButton`, `error`, `layout` |
| `PayabliPayInInputStyle` | `font`, `uiFont`, `textColor`, `placeholderColor`, `backgroundColor`, `focusedBackgroundColor`, `borderColor`, `focusedBorderColor`, `borderWidth`, `focusedBorderWidth`, `cornerRadius`, `pickerIconColor` |
| `PayabliPayInSubmitButtonStyle` | `font`, `backgroundColor`, `foregroundColor`, `disabledBackgroundColor`, `disabledForegroundColor`, `cornerRadius`, `height`, `horizontalPadding` |
| `PayabliPayInLayoutStyle` | `contentSpacing`, `headerSpacing`, `fieldGroupSpacing`, `pairedFieldSpacing`, `labelSpacing`, `sectionSpacing`, `sectionTitleSpacing`, `inputVerticalSpacing`, `inputHorizontalSpacing` |

Apply style inline:

```swift
PayabliPayInView(
    component: paymentFlow,
    configuration: configuration,
    style: payabliStyle,
    onCompleted: { _ in }
)
```

Apply style through environment:

```swift
PayabliPayInView(
    component: paymentFlow,
    configuration: configuration,
    onCompleted: { _ in }
)
.payabliPayInStyle(payabliStyle)
```

### Custom Fonts

The SDK can use any font available to the host app.

1. Add `.ttf` or `.otf` files to the app target.
2. Add the filenames to `UIAppFonts` in `Info.plist`.
3. Use `Font.custom(_:size:)` for SwiftUI text styles.
4. Use `UIFont(name:size:)` in `PayabliPayInInputStyle.uiFont` for
   UIKit-backed input fields.

Example:

```swift
let style = PayabliPayInStyle(
    title: PayabliPayInTextStyle(
        font: .custom("Inter-SemiBold", size: 20),
        color: .primary
    ),
    input: PayabliPayInInputStyle(
        font: .custom("Inter-Regular", size: 16),
        uiFont: UIFont(name: "Inter-Regular", size: 16)
    )
)
```

If `UIFont(name:size:)` returns nil, verify the font's PostScript name and
`UIAppFonts` entry.

## 12. Sheet Configuration Reference

```swift
let sheetConfiguration = PayabliPayInSheetConfiguration(
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

## 13. Request Configuration Reference

### `PayabliPayInPaymentDetails`

| Field | Description |
| --- | --- |
| `totalAmount` | Required amount. Must be greater than 0. |
| `serviceFee` | Optional service fee. Must not be negative. Serialized as currency, for example `0.10`. |
| `currency` | Optional currency, for example `USD`. |
| `checkNumber` | Optional check number for check workflows. |
| `checkUniqueId` | Optional check unique ID for check workflows. |

### `PayabliPayInRequestConfiguration`

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

### `PayabliPayInCustomerData`

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

### `PayabliPayInValidation`

| Field | Default | Description |
| --- | --- | --- |
| `requiresLuhnCheck` | true | Runs client-side Luhn validation for cards. |
| `validatesRoutingNumberChecksum` | true | Runs client-side routing number checksum validation. |

## 14. Result Handling

```swift
func handle(_ result: PayabliPayInResult) {
    switch result.kind {
    case .storedPaymentMethod:
        // A stored-method id is a token: keep it, do not log it.
        storedMethodId = result.storedPaymentMethod?.storedMethodId
        storedMethodType = result.storedPaymentMethod?.method

    case .transaction:
        paymentTransId = result.transaction?.paymentTransId
    }
}
```

`PayabliPayInResult` fields:

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
- `method`, the `PayabliPayInStoredMethodType` to charge it as
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

## 15. Diagnostics

Diagnostics are disabled by default:

```swift
let paymentFlow = PayabliPayIn(
    session: PayabliSession(config: try PayabliConfig(
        entryPoint: entryPoint,
        environment: .sandbox,
        tokenProvider: { try await backend.fetchPayInAccessToken() }
    )),
    diagnostics: .disabled
)
```

Enable diagnostics for QA:

```swift
let diagnostics = PayabliPayInDiagnostics.enabled { entry in
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
tokens, access tokens, client secrets, card number, CVV, account number, routing, stored method IDs, customer IDs, names, emails, phones, and addresses.

## 16. Accessibility Checklist

When customizing:

- Keep input and submit heights at or above the SDK minimum touch target.
- If visual labels are hidden, keep `fieldLabels` meaningful for accessibility.
- Do not put clear PAN, CVV, account number, routing number, tokens, or customer
  contact values in custom labels, placeholders, diagnostics, or result UI.
- Keep section titles concise and meaningful.
- Test Dynamic Type, especially accessibility sizes.
- Ensure custom colors have sufficient contrast.

## 17. Bridge Scope

Flutter, React Native, and .NET MAUI bridges currently expose stored card/bank account
payment-method creation. Native Swift integrations should call
`PayabliSDKPayIn` directly for capture, authorize, capture-authorized
and void transaction flows until those request models are added to the bridge
APIs.

The `@objc` bridge covers `addCard` and `addBankAccount` only. `voidTransaction(_:)` is
not bridged, which matches capture, authorize and `captureAuthorizedTransaction`
rather than being an omission.

The React Native Expo QA app is under `Example/PayabliReactNativeDemo`.

## 18. Testing

Run component tests:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPayInTests
```

Run coverage:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPayInTests \
  -enableCodeCoverage YES \
  -resultBundlePath build/TestResults/PayInCoverage.xcresult

xcrun xccov view --report build/TestResults/PayInCoverage.xcresult
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
