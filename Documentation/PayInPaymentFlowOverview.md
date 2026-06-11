# PayabliSDKPayInPaymentFlow Overview

`PayabliSDKPayInPaymentFlow` is the unified iOS PayIn component for native
Payabli payment flows. It replaces the older separate payment-method and
payment-capture components with one Swift package product that can store payment
methods, submit MoneyIn transactions, and render an SDK-owned SwiftUI form.

Add the product:

```swift
.product(name: "PayabliSDKPayInPaymentFlow", package: "sdk-ios")
```

Import:

```swift
import PayabliSDKPayInPaymentFlow
```

## Why We Built This

PayIn integrations often need more than one payment path: saving a card or bank
account, charging immediately, authorizing a card for later capture, or
capturing a prior authorization. Before this component, those jobs were split
across separate payment-method and payment-capture surfaces, which made native
iOS integrations harder to configure, secure, test, and document consistently.

`PayabliSDKPayInPaymentFlow` provides one native SwiftUI and async API surface
for the common PayIn lifecycle. It centralizes mobile access-token usage,
SDK-owned sensitive-field collection, MoneyIn request construction, result
handling, diagnostics redaction, accessibility behavior, and visual
customization so host apps can choose between a low-PCI hosted form and direct
PCI-sensitive APIs without switching components.

## Overall Capabilities

At a high level, the component provides:

- hosted SwiftUI payment forms that can render inline or in a sheet
- direct async APIs for advanced or server-controlled workflows
- card and ACH payment-method storage through Token Storage
- MoneyIn capture for SDK-collected card or ACH details in the hosted form
- MoneyIn capture for card, ACH, stored method, cloud device, check, and cash
  through the direct API
- card authorization and follow-up capture of a prior authorization
- configurable fields, field order, sections, labels, placeholders, hidden
  values, validation, payment summary rows, and visual styling
- redacted diagnostics, stable accessibility identifiers, Dynamic Type support,
  and unified stored-method or transaction results

## What The Component Does

The component supports four PayIn workflows:

| Workflow | API surface | Endpoint family | Notes |
| --- | --- | --- | --- |
| Store card or ACH payment method | Hosted form and direct async API | `/api/TokenStorage/add` | Use hosted form when the host app must not access clear PAN. |
| Capture transaction | Hosted form and direct async API | `/api/v2/MoneyIn/getpaid` | Hosted form collects card or ACH; direct API also supports stored, cloud, check, and cash methods. |
| Authorize transaction | Hosted form and direct async API | `/api/v2/MoneyIn/authorize` | Card-only today. ACH and stored methods are not valid authorize inputs. |
| Capture prior authorization | Direct async API | `/api/v2/MoneyIn/capture/{transId}` | Uses a prior authorization transaction ID. |

`PayabliPayInPaymentFlowOperation` selects the hosted form behavior:

- `.storePaymentMethod`
- `.capture`
- `.authorize`

The default is `.storePaymentMethod`.

## Authentication Model

Every operation uses a mobile access-token provider:

```swift
let paymentFlow = PayabliPayInPaymentFlow(
    entryPoint: entryPoint,
    environment: .sandbox,
    accessTokenProvider: {
        try await backend.fetchPayInAccessToken()
    }
)
```

The host app should fetch short-lived Payabli access tokens from its own
backend. Do not embed `clientSecret` values in the app. Capture and authorize
use the same provider approach as stored-method requests; they do not require
integrators to manually supply a `requestToken` header.

## Hosted Form Versus Direct API

The hosted SwiftUI form and sheet are recommended for integrations where the
host app must avoid direct access to clear card data. In hosted form mode:

- the SDK owns card and ACH field state
- clear PAN is not written into host-visible `UITextField.text`
- PAN, CVV, ACH account, routing number, tokens, and customer contact fields are
  redacted from diagnostics
- accessibility values do not expose sensitive values
- completion callbacks return stored-method or transaction results, not raw
  card or bank data

Direct APIs are available for advanced or server-controlled workflows, but they
are PCI-sensitive because the host app constructs and passes card or ACH data.

## Hosted UI Capabilities

`PayabliPayInPaymentFlowView` can be embedded inline. The sheet modifier
`.payabliPayInPaymentFlowSheet(...)` presents the same component in SwiftUI
sheet form.

The hosted form supports:

- card and ACH method selection for store and capture flows
- card-only method selection for authorize flows
- inline form or sheet presentation
- configurable form title, subtitle, submit button text, labels, and
  placeholders
- global label layout: visible external labels or placeholder-first input text
- per-field label hiding while preserving accessibility labels
- configurable field order
- configurable sections such as `Card Information`, `Customer Information`, and
  `Payment Information`
- configurable section names
- per-section section title style
- global vertical and horizontal input spacing
- per-section vertical and horizontal input spacing
- per-field vertical spacing after specific inputs
- required optional customer fields
- hidden values for ACH holder type, SEC code, ACH device, method description,
  and customer data
- card brand detection with leading, trailing, or hidden brand icons
- read-only amount and fee summary rows for capture and authorize
- configurable fonts, colors, borders, input sizing, button styling, and layout
- Dynamic Type and accessibility-size layout behavior

## Field And Section Model

Fields are represented by `PayabliPayInPaymentFlowField`. They can be ordered
flatly with `cardFieldOrder` and `achFieldOrder`, or grouped into sections with
`cardSections` and `achSections`.

Supported fields:

| Field | Default label | Use |
| --- | --- | --- |
| `.cardholderName` | Name on card | Card input |
| `.cardNumber` | Card number | Card input |
| `.cardExpiration` | Expiration | Card input |
| `.cardCvv` | CVV | Card input |
| `.cardZip` | Postal Code | Card input |
| `.achHolder` | Account holder | ACH input |
| `.achRouting` | Routing number | ACH input |
| `.achAccount` | Account number | ACH input |
| `.achAccountType` | Account type | ACH input |
| `.achHolderType` | Holder type | ACH input or hidden value |
| `.achSecCode` | SEC code | Hidden by default |
| `.achDevice` | Device | Optional ACH metadata |
| `.methodDescription` | Description | Stored-method metadata |
| `.firstName` | First name | Customer information |
| `.lastName` | Last name | Customer information |
| `.customerNumber` | Customer number | Customer information |
| `.billingEmail` | Billing email | Customer information |
| `.billingZip` | Billing Postal Code | Customer information |
| `.amount` | Amount | Read-only payment summary |
| `.serviceFee` | Fee | Read-only payment summary |

Section names are fully configurable:

```swift
PayabliPayInPaymentFlowFieldSection(
    title: "Customer Information",
    fields: [.firstName, .lastName, .billingEmail, .billingZip]
)
```

Each section can also configure:

- `titleStyle`
- `inputVerticalSpacing`
- `inputHorizontalSpacing`
- `fieldVerticalSpacings`

## Labels And Placeholders

`PayabliPayInPaymentFlowLabels` controls:

- `title`
- `subtitle`
- `submitButton`
- `fieldLabels`
- `fieldPlaceholders`

Labels and placeholders are independent. An integrator can hide visible labels
and use placeholder text while the component continues to use the label strings
for accessibility.

```swift
let labels = PayabliPayInPaymentFlowLabels(
    title: "Payment",
    submitButton: "Submit Payment",
    fieldPlaceholders: [
        .cardholderName: "Name on card",
        .cardNumber: "Card number",
        .cardExpiration: "Expiration",
        .cardCvv: "CVV",
        .cardZip: "Postal Code"
    ]
)

let configuration = PayabliPayInPaymentFlowFormConfiguration(
    labels: labels,
    labelLayout: .placeholder,
    showsFieldLabels: false,
    hiddenFieldLabels: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]
)
```

The default card postal-code label is `Postal Code`; customer billing postal
code is `Billing Postal Code`.

## Payment Summary

Capture and authorize forms include a non-editable payment summary section
before the submit button. By default it displays generated values from
`PayabliPayInPaymentFlowPaymentDetails`:

- `Amount: $ 1.00`
- `Fee: $ 0.10`

The text and styling are configurable through
`PayabliPayInPaymentFlowPaymentSummaryConfiguration`:

- `amountLabelText`
- `amountValueText`
- `feeLabelText`
- `feeValueText`
- `currencySymbol`
- `labelStyle`
- `valueStyle`
- `rowSpacing`

Rows are vertical. Labels are left aligned and values are right aligned.

## Styling Capabilities

Use `PayabliPayInPaymentFlowStyle` to style the hosted form.

Configurable style areas:

| Style area | Fields |
| --- | --- |
| Form title | `font`, `color` |
| Subtitle | `font`, `color` |
| Section titles | `font`, `color`, plus per-section overrides |
| Labels | `font`, `color` |
| Inputs | SwiftUI font, UIKit input font, text color, placeholder color, background, focused background, border colors, border widths, corner radius, picker icon color |
| Submit button | font, background, foreground, disabled colors, corner radius, height, horizontal padding |
| Error message | `font`, `color` |
| Layout | content, header, field, paired-field, label, section, and section-title spacing |

Custom fonts are supplied by the host application. Add the font files to the
app target, list them in `UIAppFonts`, use `Font.custom(_:size:)` for SwiftUI
text, and set `PayabliPayInPaymentFlowInputStyle.uiFont` for UIKit-backed input
text.

## Direct API Payment Methods

Direct capture supports these payment method cases:

- `.card(PayabliPayInPaymentFlowCardMethod)`
- `.ach(PayabliPayInPaymentFlowACHMethod)`
- `.stored(PayabliPayInPaymentFlowStoredMethod)`
- `.cloud(PayabliPayInPaymentFlowCloudMethod)`
- `.check(PayabliPayInPaymentFlowCheckMethod)`
- `.cash`

Direct authorize supports card only today:

```swift
try await paymentFlow.authorize(PayabliPayInPaymentFlowRequest(
    paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 1.00),
    paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(data: cardData))
))
```

## Results

`PayabliPayInPaymentFlowResult` is a unified result wrapper:

- `kind == .storedPaymentMethod` for token-storage success
- `storedPaymentMethod` contains stored-method identifiers and response text
- `kind == .transaction` for capture, authorize, and capture-authorized success
- `transaction` contains transaction IDs, method, amount, status, response data,
  and other MoneyIn response fields
- `apiResponse` carries the full MoneyIn response for transaction operations

## Diagnostics And Redaction

Diagnostics are disabled by default. When enabled, request, response, and
failure events are delivered through a handler. Diagnostics redact sensitive
headers and bodies, including access tokens, request tokens, card data, ACH
data, stored method identifiers, customer identifiers, emails, phones, and
addresses.

```swift
let diagnostics = PayabliPayInPaymentFlowDiagnostics.enabled { entry in
    print(entry.phase, entry.method, entry.statusCode ?? 0)
}
```

## Bridge Scope

Flutter, React Native, and .NET MAUI bridge files currently expose stored card
and ACH payment-method creation. Native Swift apps should call
`PayabliSDKPayInPaymentFlow` directly for capture, authorize, and
capture-authorized transaction flows until those request models are promoted
into the bridge APIs.

## Reference Docs

- `Sources/PayabliSDKPayInPaymentFlow/LLM.md`: exhaustive local reference for
  code generation and field-level configuration.
- `Documentation/PayInPaymentFlowIntegrationGuide.md`: step-by-step integration
  guide with detailed examples.
