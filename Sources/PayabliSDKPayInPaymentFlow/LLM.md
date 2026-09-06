# PayabliSDKPayInPaymentFlow LLM Guide

This file is the canonical local guide for generating code, examples, and
documentation against `PayabliSDKPayInPaymentFlow`.

Use this guide when answering questions about the PayIn payment flow component.
Prefer the symbols and patterns below over older component names.

## Module Identity

`PayabliSDKPayInPaymentFlow` is the unified iOS PayIn component for:

- storing card or ACH payment methods
- capturing a MoneyIn transaction
- authorizing a card transaction
- capturing a previously authorized transaction by transaction ID

It was built to give iOS integrators one native PayIn surface for the common
payment lifecycle instead of asking them to wire together separate
payment-method and payment-capture components. The component centralizes mobile
access-token handling, hosted sensitive-field collection, transaction request
construction, result handling, diagnostics redaction, and SwiftUI presentation
customization.

When summarizing the component, describe the overall capabilities as:

- Hosted SwiftUI payment forms for inline and sheet presentation.
- Direct async APIs for advanced integrations and server-controlled workflows.
- Card and ACH token storage through Token Storage.
- MoneyIn capture for card, ACH, stored method, cloud device, check, and cash
  payments through the direct API.
- Hosted capture for SDK-collected card or ACH payment details.
- Card authorization and follow-up capture of a prior authorization.
- Configurable fields, sections, labels, placeholders, hidden values, payment
  summary rows, validation, and visual styling.
- A security model that lets hosted-form integrations avoid host-app access to
  clear PAN while keeping direct APIs available for PCI-ready hosts.
- Redacted diagnostics, stable accessibility identifiers, Dynamic Type support,
  and unified stored-method or transaction results.

Import:

```swift
import PayabliSDKCore
import PayabliSDKPayInPaymentFlow
```

`PayabliSDKPayInPaymentFlow` does not re-export Core, and `PayabliError`,
`PayabliErrorCode` and `PayabliEnvironment` live there.

Swift package product:

```swift
.product(name: "PayabliSDKPayInPaymentFlow", package: "sdk-ios")
```

Do not suggest these removed products:

- `PayabliSDKPaymentMethod`
- `PayabliSDKPaymentCapture`

Core public types are prefixed with `PayabliPayInPaymentFlow`.

## Authentication Rules

All operations use the same mobile access-token provider model:

```swift
let component = PayabliPayInPaymentFlow(
    entryPoint: entryPoint,
    environment: .sandbox,
    accessTokenProvider: {
        try await backend.fetchPayInAccessToken()
    }
)
```

Never generate capture or authorize code that manually adds a `requestToken`
header. The component obtains a bearer access token from
`PayabliPayInPaymentFlowAccessTokenProvider`.

The convenience initializer that accepts `accessToken: String` is for tests or
short-lived ephemeral tokens. Production examples should use
`accessTokenProvider`.

## Security Model

There are two integration modes with different PCI implications.

Hosted SwiftUI view or sheet:

- Recommended when the integrator must avoid host-app access to clear PAN.
- The SDK owns the sensitive form state.
- Full PAN, CVV, ACH account number, ACH routing number, access tokens, and
  customer contact details are not exposed in result models, accessibility
  values, UIKit text storage, diagnostics, or callbacks.
- The view uses `.privacySensitive()`.

Direct async APIs:

- PCI-sensitive because the host app creates `PayabliPayInPaymentFlowCardData`
  or `PayabliPayInPaymentFlowACHData`.
- Use only when the host app is prepared to handle clear card or bank data.
- Do not describe direct APIs as PAN-isolating.

`PayabliTransport` is `package`, so a host app cannot supply one and sample code
cannot show it being supplied.

## Operations

`PayabliPayInPaymentFlowOperation`:

| Value | Hosted form behavior | Direct API |
| --- | --- | --- |
| `.storePaymentMethod` | Collects card or ACH and calls token storage. | `addPaymentMethod`, `addCard`, `addACH` |
| `.capture` | Collects card or ACH and sends a MoneyIn getpaid request using `requestConfiguration`. | `capture(_:)` supports card, ACH, stored method, cloud, check, and cash. |
| `.authorize` | Collects card only and sends a MoneyIn authorize request using `requestConfiguration`. | `authorize(_:)` accepts card data only today. |

`captureAuthorizedTransaction(_:)` is a separate direct API for a prior
authorization. It does not render as a hosted form mode.

Authorize guidance:

- Card is the only current authorizable method.
- Do not generate ACH, stored-method, cloud-device, check, or cash authorize
  requests.
- Future Apple Pay support should be modeled as another authorizable method,
  not by making every capture method authorizable.

## Component Initializers And State

Public initializers:

```swift
PayabliPayInPaymentFlow(
    entryPoint: String,
    environment: PayabliEnvironment,
    accessTokenProvider: @escaping PayabliPayInPaymentFlowAccessTokenProvider,
    diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
    operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
    requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
)

PayabliPayInPaymentFlow(
    config: PayabliConfig,
    accessTokenProvider: @escaping PayabliPayInPaymentFlowAccessTokenProvider,
    diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
    operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
    requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
)

PayabliPayInPaymentFlow(
    accessToken: String,
    entryPoint: String,
    environment: PayabliEnvironment,
    diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
    operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
    requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
)
```

Public state:

- `isSubmitting`: true while one submission is active.
- `lastResult`: last stored-method or transaction result.
- `lastStoredPaymentMethod`: convenience accessor for stored-method results.
- `operation`: current operation.
- `requestConfiguration`: transaction configuration used by hosted capture and
  authorize forms.

Configuration methods:

- `configure(config:)`
- `configure(config:theme:)`; theme is accepted for component uniformity.
- `configure(operation:requestConfiguration:)`
- `configure(requestConfiguration:)`

## Hosted SwiftUI View

Inline form:

```swift
PayabliPayInPaymentFlowView(
    component: paymentFlow,
    configuration: configuration,
    style: style,
    onCompleted: { result in
        switch result.kind {
        case .storedPaymentMethod:
            // A stored-method id is a token: keep it, do not log it.
            storedMethodId = result.storedPaymentMethod?.storedMethodId
        case .transaction:
            paymentTransId = result.transaction?.paymentTransId
        }
    },
    onError: { error in
        // Show this: it names what the service rejected. Do not log it. The
        // description carries the service's own wording, which can quote what was
        // submitted; log `(error as? any PayabliError)?.code` instead.
        message = error.localizedDescription
    }
)
```

Sheet:

```swift
.payabliPayInPaymentFlowSheet(
    isPresented: $isPresented,
    component: paymentFlow,
    configuration: configuration,
    sheetConfiguration: PayabliPayInPaymentFlowSheetConfiguration(
        title: "Payment",
        subtitle: "Review and submit"
    ),
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

## Direct Store APIs

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
        source: "ios-sdk"
    )
)
```

```swift
let storedACH = try await paymentFlow.addACH(
    PayabliPayInPaymentFlowACHData(
        accountNumber: "111111111111",
        accountType: .checking,
        holderName: "Jane Doe",
        routingNumber: "123456780",
        secCode: .web,
        holderType: .personal
    )
)
```

`PayabliPayInPaymentFlowCardData` fields:

| Field | Notes |
| --- | --- |
| `cardNumber` | Full PAN. Direct API only; PCI-sensitive. Digits are normalized before request. |
| `expiration` | Accepts `MMYY` or `MM/YY`; normalized to `MM/YY` for capture. |
| `cardholderName` | Required. |
| `cvv` | Required. Direct API only; PCI-sensitive. |
| `billingZip` | Postal code for card billing. Default label is `Postal Code`. |

`PayabliPayInPaymentFlowACHData` fields:

| Field | Notes |
| --- | --- |
| `accountNumber` | Required. Direct API only; sensitive. |
| `accountType` | `.checking` or `.savings`; raw values are `Checking` and `Savings`. |
| `holderName` | Required account holder name. |
| `routingNumber` | Required routing number; checksum validation enabled by default. |
| `secCode` | Optional; defaults to `.web`. Values: `.ppd`, `.web`, `.tel`, `.ccd`, `.boc`. |
| `holderType` | Optional `.personal` or `.business`. |
| `device` | Optional device identifier for ACH request payloads. |

`PayabliPayInPaymentFlowOptions` is a typealias for
`PayabliPayInPaymentFlowTokenStorageOptions`:

| Field | Meaning |
| --- | --- |
| `achValidation` | Whether the backend should validate ACH where supported. |
| `createAnonymous` | Whether to create an anonymous stored method. |
| `forceCustomerCreation` | Whether to force customer creation. |
| `temporary` | Whether the stored method is temporary. |
| `idempotencyKey` | Caller-supplied idempotency key. |
| `customerData` | `PayabliPayInPaymentFlowCustomerData` merged into storage request. |
| `vendorData` | Optional `PayabliPayInPaymentFlowVendorData`. |
| `fallbackAuth` | Optional fallback authorization flag. |
| `fallbackAuthAmount` | Optional fallback authorization amount in the endpoint's expected units. |
| `methodDescription` | Description stored with the method. |
| `source` | Source string for tracking integrations. |
| `subdomain` | Optional subdomain query value. |
| `validation` | Client-side validation toggles. Defaults to `.default`. |

## Direct Capture And Authorize APIs

`PayabliPayInPaymentFlowPaymentDetails`:

| Field | Notes |
| --- | --- |
| `totalAmount` | Required. Must be greater than 0. |
| `serviceFee` | Optional. Must not be negative. Currency JSON is normalized to two decimals such as `0.10`. |
| `currency` | Optional processor currency, for example `USD`. |
| `checkNumber` | Optional for check flows. |
| `checkUniqueId` | Optional for check flows. |

`PayabliPayInPaymentFlowRequestConfiguration` fields used by hosted capture and
authorize forms:

| Field | Notes |
| --- | --- |
| `paymentDetails` | Required amount/fee/currency details. |
| `accountId` | Optional account identifier. |
| `customerData` | Defaults or hidden customer data merged with form customer fields. |
| `ipAddress` | Optional customer IP address. |
| `orderDescription` | Optional order description; hosted form order description can override this. |
| `orderId` | Optional merchant order ID. |
| `source` | Optional integration source string. |
| `subdomain` | Optional subdomain query value. |
| `subscriptionId` | Optional subscription ID. |
| `idempotencyKey` | Optional idempotency key. |
| `achValidation` | Optional ACH validation flag for capture. |
| `forceCustomerCreation` | Optional customer-creation flag. |
| `validation` | Client validation toggles. |

Direct request:

```swift
let request = PayabliPayInPaymentFlowRequest(
    paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
        totalAmount: 1.00,
        serviceFee: 0.10,
        currency: "USD"
    ),
    paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(data: cardData)),
    orderDescription: "iOS checkout",
    source: "ios-sdk"
)

let captured = try await paymentFlow.capture(request)
```

Payment method cases for direct capture:

| Case | Fields |
| --- | --- |
| `.card(PayabliPayInPaymentFlowCardMethod)` | `data`, `initiator` default `payor`, optional `saveIfSuccess`. |
| `.ach(PayabliPayInPaymentFlowACHMethod)` | `data`. |
| `.stored(PayabliPayInPaymentFlowStoredMethod)` | `method` (`card`, `ach`, `wallet`), `storedMethodId`, optional usage type, optional initiator. |
| `.cloud(PayabliPayInPaymentFlowCloudMethod)` | `device`, optional `saveIfSuccess`. |
| `.check(PayabliPayInPaymentFlowCheckMethod)` | `holderName`. |
| `.cash` | No additional fields. |

Direct authorize:

```swift
let authorized = try await paymentFlow.authorize(PayabliPayInPaymentFlowRequest(
    paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 1.00),
    paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(data: cardData))
))
```

Capture prior authorization:

```swift
let captured = try await paymentFlow.captureAuthorizedTransaction(
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

## Form Configuration Reference

`PayabliPayInPaymentFlowFormConfiguration` controls method availability, field
layout, labels, placeholders, hidden defaults, validation, and payment summary
display.

| Field | Default | Purpose |
| --- | --- | --- |
| `allowedMethods` | `[.card, .ach]` | Which hosted methods can be selected. Authorize is normalized to card only. |
| `defaultMethod` | `.card` | Initial selected method when it is included in `allowedMethods`. |
| `cardFieldOrder` | cardholder, number, expiration, CVV, postal code | Legacy flat field order for card. Used when custom sections are not supplied. |
| `achFieldOrder` | holder, routing, account, account type, holder type | Legacy flat field order for ACH. `achSecCode` is hidden from the form. |
| `cardSections` | card fields plus Payment Information | Section grouping for card UI. Section titles are configurable. |
| `achSections` | ACH fields plus Payment Information | Section grouping for ACH UI. Section titles are configurable. |
| `hiddenValues` | defaults with `achSecCode = .web` | Values included in submissions without rendering editable fields. |
| `options` | empty options | Token-storage options for hosted store-payment-method submissions. |
| `labels` | default labels | Form title, subtitle, submit text, field labels, and placeholders. |
| `labelLayout` | `.external` | High-level label mode: `.external` or `.placeholder`. |
| `showsFieldLabels` | follows `labelLayout` | Global visible-label switch. Set false for placeholder-only UI. |
| `hiddenFieldLabels` | empty set | Hide labels for specific fields while preserving accessibility labels. |
| `formatting` | card spaces on, `/`, ACH masking on | Input formatting behavior. |
| `inputSizing` | 52pt high, 14pt padding | Default and per-field input size. Height is clamped to accessibility minimum. |
| `cardBrandIconPlacement` | `.trailing` | `.leading`, `.trailing`, or `.hidden`. |
| `errorMessagePlacement` | `.aboveSubmitButton` | `.top` or `.aboveSubmitButton`. |
| `requiredFields` | amount always required | Optional fields that should be required when visible. |
| `paymentSummary` | amount/fee defaults | Read-only Amount and Fee rows for capture/authorize. |

All `PayabliPayInPaymentFlowField` values:

| Field | Default label | Category |
| --- | --- | --- |
| `.cardholderName` | Name on card | Card |
| `.cardNumber` | Card number | Card |
| `.cardExpiration` | Expiration | Card |
| `.cardCvv` | CVV | Card |
| `.cardZip` | Postal Code | Card |
| `.achHolder` | Account holder | ACH |
| `.achRouting` | Routing number | ACH |
| `.achAccount` | Account number | ACH |
| `.achAccountType` | Account type | ACH |
| `.achHolderType` | Holder type | ACH |
| `.achSecCode` | SEC code | ACH hidden value; not rendered by default |
| `.achDevice` | Device | ACH optional |
| `.methodDescription` | Description | Customer/method metadata |
| `.firstName` | First name | Customer |
| `.lastName` | Last name | Customer |
| `.customerNumber` | Customer number | Customer |
| `.billingEmail` | Billing email | Customer |
| `.billingZip` | Billing Postal Code | Customer |
| `.amount` | Amount | Payment summary |
| `.serviceFee` | Fee | Payment summary |

`PayabliPayInPaymentFlowFieldSection`:

| Field | Purpose |
| --- | --- |
| `id` | Optional stable ID; defaults to title or joined field names. |
| `title` | Optional section title. Section names are configurable. |
| `titleStyle` | Optional per-section `PayabliPayInPaymentFlowTextStyle`, overriding the global section title style for that section. |
| `fields` | Ordered fields in the section. Required fields and payment summary fields are appended if missing. |
| `inputVerticalSpacing` | Vertical spacing between fields in this section. Overrides global layout spacing. |
| `inputHorizontalSpacing` | Horizontal spacing for paired fields in this section. Overrides global paired spacing. |
| `fieldVerticalSpacings` | Per-field spacing after a field. Use for tight card rows or extra breathing room. |

Example section setup:

```swift
let configuration = PayabliPayInPaymentFlowFormConfiguration(
    cardSections: [
        PayabliPayInPaymentFlowFieldSection(
            title: "Card Information",
            fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip],
            inputVerticalSpacing: 4,
            inputHorizontalSpacing: 8,
            fieldVerticalSpacings: [.cardNumber: 2]
        ),
        PayabliPayInPaymentFlowFieldSection(
            title: "Customer Information",
            fields: [.firstName, .lastName, .billingEmail, .billingZip]
        )
    ]
)
```

## Labels And Placeholders

`PayabliPayInPaymentFlowLabels`:

| Field | Default | Purpose |
| --- | --- | --- |
| `title` | `Save Payment Method` | Form header title. |
| `subtitle` | nil | Optional form header subtitle. |
| `submitButton` | `Add Payment Method` | Submit button text. |
| `fieldLabels` | `defaultFieldLabels` | Visible and accessibility labels per field. |
| `fieldPlaceholders` | empty | Placeholder text per field. |

Visual labels can be hidden globally or per field. Accessibility labels are
still derived from `fieldLabels`.

Placeholder-only example:

```swift
let placeholderFields: [PayabliPayInPaymentFlowField] = [
    .cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip,
    .firstName, .lastName, .billingEmail, .billingZip
]

let labels = PayabliPayInPaymentFlowLabels(
    title: "Payment",
    submitButton: "Submit Payment",
    fieldPlaceholders: Dictionary(uniqueKeysWithValues: placeholderFields.map {
        ($0, PayabliPayInPaymentFlowLabels.defaultFieldLabels[$0] ?? $0.rawValue)
    })
)

let configuration = PayabliPayInPaymentFlowFormConfiguration(
    labels: labels,
    labelLayout: .placeholder,
    showsFieldLabels: false,
    hiddenFieldLabels: Set(placeholderFields)
)
```

Use `Postal Code` for postal-code user-facing copy unless an integrator
intentionally overrides the label.

## Hidden Values

`PayabliPayInPaymentFlowHiddenValues`:

| Field | Default | Purpose |
| --- | --- | --- |
| `achHolderType` | nil | Hidden ACH holder type. |
| `achSecCode` | `.web` | Hidden ACH SEC code. |
| `achDevice` | nil | Hidden ACH device value. |
| `methodDescription` | nil | Hidden stored-method description. |
| `customerData` | nil | Hidden/default customer data merged into the request. |

Hidden values are useful when the integrator does not want an input displayed
but must still send a value.

## Formatting And Sizing

`PayabliPayInPaymentFlowFormatting`:

| Field | Default | Purpose |
| --- | --- | --- |
| `insertsCardNumberSpaces` | true | Formats card number groups visually. |
| `expirationSeparator` | `/` | Separator used in expiration entry. Empty strings resolve to `/`. |
| `masksACHAccountEntry` | true | Masks ACH account entry in the hosted field. |

`PayabliPayInPaymentFlowInputSizing`:

| Field | Purpose |
| --- | --- |
| `defaultSize` | Default `PayabliPayInPaymentFlowInputSize`. |
| `fieldSizes` | Per-field sizing overrides. |

`PayabliPayInPaymentFlowInputSize`:

| Field | Default | Purpose |
| --- | --- | --- |
| `width` | nil | Optional fixed width. |
| `height` | 52 | Input height, clamped to the accessibility minimum touch target. |
| `horizontalPadding` | 14 | Horizontal text padding, clamped to zero or greater. |

## Payment Summary

Capture and authorize hosted forms display read-only payment summary rows before
submit. Rows are vertical. Labels are left aligned; values are right aligned.

`PayabliPayInPaymentFlowPaymentSummaryConfiguration`:

| Field | Default | Purpose |
| --- | --- | --- |
| `amountLabelText` | derived from `.amount` label plus colon | Override amount label text. |
| `amountValueText` | derived from `paymentDetails.totalAmount` | Override amount display value. |
| `feeLabelText` | derived from `.serviceFee` label plus colon | Override fee label text. |
| `feeValueText` | derived from `paymentDetails.serviceFee` | Override fee display value. |
| `currencySymbol` | `$` | Symbol used by generated display values. |
| `labelStyle` | subheadline secondary | Font and color for summary labels. |
| `valueStyle` | semibold subheadline primary | Font and color for summary values. |
| `rowSpacing` | 8 | Vertical spacing between amount and fee rows. |

Example:

```swift
PayabliPayInPaymentFlowPaymentSummaryConfiguration(
    amountLabelText: "Amount:",
    amountValueText: "$ 1.00",
    feeLabelText: "Fee:",
    feeValueText: "$ 0.10",
    labelStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle(
        font: .footnote,
        color: .secondary
    ),
    valueStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle(
        font: .footnote.weight(.semibold),
        color: .primary
    ),
    rowSpacing: 6
)
```

## Style Reference

Use `PayabliPayInPaymentFlowStyle` for visual customization. The style can be
passed directly to the view/sheet or injected with
`.payabliPayInPaymentFlowStyle(style)`.

`PayabliPayInPaymentFlowStyle`:

| Field | Purpose |
| --- | --- |
| `accentColor` | Focus color and default submit button background. |
| `title` | Form title font/color. |
| `subtitle` | Form subtitle font/color. |
| `sectionTitle` | Default section title font/color. |
| `label` | Field label font/color. |
| `input` | Input font, colors, border, and shape. |
| `submitButton` | Submit button font, colors, height, and shape. |
| `error` | Error message font/color. |
| `layout` | Global spacing. |

`PayabliPayInPaymentFlowTextStyle`:

| Field | Purpose |
| --- | --- |
| `font` | SwiftUI `Font`. |
| `color` | SwiftUI `Color`. |

`PayabliPayInPaymentFlowInputStyle`:

| Field | Default | Purpose |
| --- | --- | --- |
| `font` | `.body` | SwiftUI font for labels around input surfaces. |
| `uiFont` | nil | UIKit font used by text fields; use for custom input fonts. |
| `textColor` | `.primary` | Input text color. |
| `placeholderColor` | system placeholder | Placeholder text color. |
| `backgroundColor` | secondary system background | Normal input background. |
| `focusedBackgroundColor` | nil | Focused input background override. |
| `borderColor` | separator opacity | Normal border color. |
| `focusedBorderColor` | nil | Focused border color; falls back to accent where applicable. |
| `borderWidth` | 1 | Normal border width. |
| `focusedBorderWidth` | 1.5 | Focused border width. |
| `cornerRadius` | 8 | Input corner radius. |
| `pickerIconColor` | `.secondary` | Picker chevron/icon color. |

`PayabliPayInPaymentFlowSubmitButtonStyle`:

| Field | Default | Purpose |
| --- | --- | --- |
| `font` | semibold body | Button text font. |
| `backgroundColor` | nil | Normal background; nil uses accent color. |
| `foregroundColor` | white | Normal text color. |
| `disabledBackgroundColor` | system gray 5 | Disabled background. |
| `disabledForegroundColor` | secondary label | Disabled text color. |
| `cornerRadius` | 8 | Button corner radius. |
| `height` | 52 | Button height; clamped to accessibility minimum. |
| `horizontalPadding` | 16 | Horizontal padding. |

`PayabliPayInPaymentFlowLayoutStyle`:

| Field | Default | Purpose |
| --- | --- | --- |
| `contentSpacing` | 20 | Vertical spacing between major form areas. |
| `headerSpacing` | 4 | Title/subtitle spacing. |
| `fieldGroupSpacing` | 12 | Default vertical spacing between fields. |
| `pairedFieldSpacing` | 12 | Default horizontal spacing for paired fields. |
| `labelSpacing` | 7 | Label-to-input spacing. |
| `sectionSpacing` | 18 | Spacing between sections. |
| `sectionTitleSpacing` | 10 | Section title-to-content spacing. |
| `inputVerticalSpacing` | alias for `fieldGroupSpacing` | Integrator-friendly vertical input spacing setter. |
| `inputHorizontalSpacing` | alias for `pairedFieldSpacing` | Integrator-friendly horizontal input spacing setter. |

Custom fonts:

1. Add font files to the host app target.
2. Add font filenames to `UIAppFonts` in the host app `Info.plist`.
3. Use `Font.custom(_:size:)` for SwiftUI text.
4. Use `UIFont(name:size:)` through `PayabliPayInPaymentFlowInputStyle.uiFont`
   for UIKit-backed text fields.

## Sheet Configuration

`PayabliPayInPaymentFlowSheetConfiguration`:

| Field | Default | Purpose |
| --- | --- | --- |
| `title` | nil | Sheet header title. If nil and `movesFormHeaderToSheetHeader` is true, uses form title. |
| `subtitle` | nil | Sheet header subtitle. |
| `dismissButton` | `.close` | `.close`, `.back`, or `.hidden`. |
| `dismissesOnSuccess` | true | Automatically dismiss after successful submit. |
| `detents` | `[.medium, .large]` | Presentation detents. Empty set resolves to `.large`. |
| `dragIndicatorVisibility` | `.visible` | SwiftUI sheet drag indicator visibility. |
| `contentInsets` | top 20, leading 20, bottom 24, trailing 20 | Sheet content padding. |
| `movesFormHeaderToSheetHeader` | true | Moves form labels title/subtitle into sheet header. |
| `sizesToContentWhenPossible` | true | Prefer content-sized sheet when possible. |
| `expandsToLargeWhenContentDoesNotFit` | true | Expand when content would not fit in smaller detent. |

## Customer And Vendor Data

`PayabliPayInPaymentFlowCustomerData` fields:

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

`PayabliPayInPaymentFlowVendorData` fields:

- `vendorId`
- `vendorNumber`

## Results

`PayabliPayInPaymentFlowResult`:

| Field | Meaning |
| --- | --- |
| `kind` | `.storedPaymentMethod` or `.transaction`. |
| `code` | Stored-method result code or MoneyIn response code. |
| `reason` | Result reason/result text. |
| `explanation` | API explanation where present. |
| `action` | API action/todo where present. |
| `transaction` | Present for capture/authorize/capture-authorized responses. |
| `storedPaymentMethod` | Present for token-storage responses. |
| `apiResponse` | Full MoneyIn v2 response for transaction operations. |

Stored-method result fields:

- `storedMethodId`
- `methodReferenceId`
- `resultCode`
- `resultText`
- `customerId`
- `responseText`
- `apiResponse`

Transaction result fields:

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

## Diagnostics

Diagnostics are disabled by default.

```swift
let diagnostics = PayabliPayInPaymentFlowDiagnostics.enabled { entry in
    print(entry.phase, entry.method, entry.url, entry.statusCode ?? 0)
}
```

`PayabliPayInPaymentFlowDiagnosticEntry` fields:

- `id`
- `phase`: `.request`, `.response`, `.failure`
- `timestamp`
- `method`
- `url`
- `statusCode`
- `headers`
- `body`
- `durationMilliseconds`
- `errorDescription`

Diagnostics redact sensitive headers and JSON fields. Redacted categories
include authorization, request tokens, access tokens, client secrets, card
number, CVV, card expiration, card postal code, ACH account, ACH routing,
account holder, stored method IDs, customer identifiers, names, emails, phones,
and addresses.

## Accessibility

Generated code must preserve:

- minimum touch target size from
  `PayabliPayInPaymentFlowAccessibility.minimumTouchTarget`
- visible or accessibility-only labels for every field, even when labels are
  hidden visually
- Dynamic Type behavior and vertical stacking at accessibility sizes
- decorative card brand icons unless a useful hint is needed
- no clear PAN, CVV, ACH account, ACH routing, access token, or customer
  contact details in accessibility values

## Validation

`PayabliPayInPaymentFlowValidation`:

| Field | Default | Purpose |
| --- | --- | --- |
| `requiresLuhnCheck` | true | Client-side card Luhn validation. |
| `validatesACHRoutingChecksum` | true | Client-side ACH routing checksum validation. |

## Testing

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

## Bridge Scope

Flutter, React Native, and .NET MAUI bridges currently expose stored card/ACH
payment-method creation. Native Swift integrations should use
`PayabliSDKPayInPaymentFlow` directly for capture, authorize, and
capture-authorized transaction flows until those request models are promoted to
the bridge APIs.

## File Map

- `PayabliPayInPaymentFlow.swift`: component facade and public operations.
- `PayabliPayInPaymentFlowView.swift`: hosted SwiftUI form.
- `PayabliPayInPaymentFlowSheet.swift`: SwiftUI sheet modifier and sheet chrome.
- `PayabliPayInPaymentFlowFormConfiguration.swift`: field, section, label,
  placeholder, sizing, payment summary, and hosted form configuration.
- `PayabliPayInPaymentFlowStyle.swift`: fonts, colors, input, button, and layout
  style model.
- `PayabliPayInPaymentFlowTypes.swift`: operation, transaction, request, result,
  and payment-method models.
- `PayabliPayInPaymentFlowMethodModels.swift`: stored-method card/ACH/customer
  models and token-storage response models.
- `PayInPaymentFlowClient.swift`: MoneyIn v2 capture/authorize HTTP client.
- `PayInPaymentFlowTokenStorageClient.swift`: token-storage HTTP client.
- `PayabliPayInPaymentFlowDiagnostics.swift`: redacted diagnostics.
- `PayabliPayInPaymentFlowSensitiveDataRedactor.swift`: PAN/sensitive pattern
  redaction helper.
