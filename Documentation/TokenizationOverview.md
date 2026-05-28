# PayabliSDKTokenization Overview

`PayabliSDKTokenization` is an opt-in Swift package product for saving card
PAN or ACH account data as a Payabli stored payment method. It calls
`POST /api/TokenStorage/add` and returns the Payabli `referenceId` as
`storedMethodId`.

The module is intentionally separate from the `PayabliSDK` umbrella. Host apps
link it only when they need card-not-present or ACH tokenization.

For step-by-step app integration, see
[`Documentation/TokenizationIntegrationGuide.md`](TokenizationIntegrationGuide.md).

## Security Model

- Do not embed a long-lived private API token in an iOS app.
- Use `PayabliTokenization(entryPoint:environment:accessTokenProvider:)` so
  the app can request a short-lived or scoped access token from your backend
  immediately before submission.
- The SwiftUI form marks its content `privacySensitive()` and clears PAN, CVV,
  ACH routing number, and ACH account number after every submit attempt.
- The module does not log PAN, CVV, ACH account numbers, routing numbers,
  access tokens, or stored method identifiers.
- Card PAN is Luhn-checked by default. ACH routing numbers are ABA-checksum
  validated by default. Disable these only when the integration has a documented
  reason.
- Integrators receive Payabli tokenization results, not raw payment values.
  Store only the returned stored-method identifier and any non-sensitive
  metadata your app needs.

## Package Integration

Add the tokenization product to the host app target:

```swift
.product(name: "PayabliSDKTokenization", package: "sdk-ios")
```

Then import the module:

```swift
import PayabliSDKCore
import PayabliSDKTokenization
```

`PayabliSDKCore` supplies shared SDK types such as `PayabliConfig`,
`PayabliEnvironment`, and `PayabliError`.

## Component Setup

Create one component instance for the screen or flow. Prefer the provider-based
initializer in production:

```swift
let tokenization = PayabliTokenization(
    entryPoint: "f743aed24a",
    environment: .sandbox,
    accessTokenProvider: {
        try await backend.fetchPayabliAccessToken()
    }
)
```

The direct `accessToken:` initializer exists for tests, demos, or public
ephemeral access tokens only.

To inspect redacted tokenization HTTP traffic during local or QA development,
pass diagnostics at component initialization:

```swift
let tokenization = PayabliTokenization(
    entryPoint: "f743aed24a",
    environment: .sandbox,
    accessTokenProvider: {
        try await backend.fetchPayabliAccessToken()
    },
    diagnostics: .enabled { entry in
        print("[\(entry.phase.rawValue)] \(entry.method) \(entry.url)")
        print(entry.headers)
        print(entry.body ?? "")
    }
)
```

`PayabliTokenizationDiagnosticEntry` includes `phase`, `method`, `url`,
`statusCode`, redacted `headers`, redacted `body`, elapsed duration for
responses/failures, and transport error text for failures.

## Public API Surface

### Component

`PayabliTokenization` is the public component facade.

| API | Purpose |
|---|---|
| `init(entryPoint:environment:accessTokenProvider:transport:diagnostics:)` | Production initializer. Fetches an access token lazily through your backend. |
| `init(config:accessTokenProvider:transport:diagnostics:)` | Uses `PayabliConfig.entryPoint` and `PayabliConfig.environment`. |
| `init(accessToken:entryPoint:environment:transport:diagnostics:)` | Convenience for tests, demos, or ephemeral public access tokens only. |
| `configure(config:)` | Repoints the component at a new entrypoint/environment. |
| `tokenize(paymentMethod:options:)` | Low-level submission API used by the component and bridge layers. |
| `tokenizeCard(_:options:)` | Low-level card helper for SDK-owned bridge layers. |
| `tokenizeACH(_:options:)` | Low-level ACH helper for SDK-owned bridge layers. |
| `isSubmitting` | Published submission state. |
| `lastTokenizedMethod` | Published last successful tokenization result. |

`transport:` is injectable for tests and advanced hosts. Production apps should
normally let the component create its default `PayabliService`.
Mobile app integrators should prefer `PayabliTokenizationView` so raw PAN,
CVV, and ACH account values stay inside the SDK-owned component instead of
host-app form code.

### Payment Method Data

The card component requires:

- `cardNumber`
- `expiration` in `MMYY` or `MM/YY` input form
- `cardholderName`
- `billingZip` / `.cardZip`

Optional card component fields:

- `cvv`

The ACH component requires:

- `accountNumber`
- `accountType` (`.checking` or `.savings`)
- `holderName`
- `routingNumber`

Optional ACH request values:

- `secCode` (`.ppd`, `.web`, `.tel`, `.ccd`, `.boc`; defaults to `.web`)
- `holderType` (`.personal` or `.business`)
- `device`

### Options

`PayabliTokenizationOptions` maps the optional API fields outside the required
payment-method values.

| Option | API location | Notes |
|---|---|---|
| `achValidation` | Query | Enables Payabli ACH validation when available for the account. |
| `createAnonymous` | Query | Creates a saved method without customer data. |
| `forceCustomerCreation` | Query | Forces a new customer record even if identifiers match. |
| `temporary` | Query | Creates a temporary one-time-use token. |
| `idempotencyKey` | Header | Recommended for retry-safe submissions. |
| `customerData` | Body | Payor/customer owner data. |
| `vendorData` | Body | Vendor owner data for ACH Pay Out use cases. |
| `fallbackAuth` | Body | Allows Payabli fallback card authorization when tokenization fails. |
| `fallbackAuthAmount` | Body | Amount for fallback auth, in cents. |
| `methodDescription` | Body | Stored method display description. |
| `source` | Body | Integration source tag. |
| `subdomain` | Body | Payment page identifier when applicable. |
| `validation` | SDK local | Luhn and ACH routing checksum policy. |

The query flags are optional `Bool?` values. `nil` means the SDK omits the
query parameter and lets Payabli apply account/API defaults. For QA flows that
should always create a customer-owned reusable stored method, use
`createAnonymous: false`, `forceCustomerCreation: true`, and
`temporary: false`.

### Diagnostics Redaction

`PayabliTokenizationDiagnostics` emits redacted request, response, and
transport-failure entries through your handler. It never exposes bearer tokens,
PAN, CVV, ACH account/routing values, cardholder/customer PII, or stored-method
identifiers. Use the entry `url` to verify environment and query flags, and the
redacted `body` to verify non-sensitive fields such as `entryPoint`, `source`,
`method`, `resultCode`, and `resultText`.

### Response

`PayabliTokenizedMethod` returns both convenience fields and the full decoded
API response.

| Property | Description |
|---|---|
| `storedMethodId` | Payabli stored method identifier. This is `responseData.referenceId`. |
| `methodReferenceId` | Payabli method reference value when present. |
| `resultCode` | Payabli result code. `1` indicates success. |
| `resultText` | Payabli result text. |
| `customerId` | Payabli customer ID when returned. |
| `responseText` | Top-level Payabli response text. |
| `apiResponse` | Full decoded `PayabliTokenizationAPIResponse`. |

Use `apiResponse` when the host application needs the complete Payabli response
for analytics, support tooling, or custom success/error handling.

## SwiftUI Form

`PayabliTokenizationView` is the turn-key SwiftUI component. Required payment
fields are enforced by the SDK. Optional visible fields are controlled by the
field-order arrays. Optional hidden values are supplied through
`PayabliTokenizationHiddenValues` or `PayabliTokenizationOptions`.

```swift
PayabliTokenizationView(
    component: tokenization,
    configuration: PayabliTokenizationFormConfiguration(
        allowedMethods: [.card, .ach],
        defaultMethod: .card,
        cardFieldOrder: [
            .cardNumber,
            .cardExpiration,
            .cardCvv,
            .cardZip,
            .cardholderName
        ],
        achFieldOrder: [
            .achHolder,
            .achRouting,
            .achAccount,
            .achAccountType
        ],
        hiddenValues: PayabliTokenizationHiddenValues(
            achHolderType: .personal,
            achSecCode: .web,
            methodDescription: "Primary payment method",
            customerData: PayabliTokenizationCustomerData(
                customerNumber: "cust-123"
            )
        ),
        options: PayabliTokenizationOptions(
            achValidation: true,
            createAnonymous: false,
            forceCustomerCreation: true,
            temporary: false,
            source: "ios-sdk"
        ),
        labels: PayabliTokenizationLabels(
            title: "Payment Method",
            subtitle: "Save a payment method for future transactions.",
            submitButton: "Save Method"
        ),
        labelLayout: .external,
        formatting: PayabliTokenizationFormatting(
            insertsCardNumberSpaces: true,
            masksACHAccountEntry: true
        ),
        inputSizing: PayabliTokenizationInputSizing(
            defaultSize: PayabliTokenizationInputSize(height: 52),
            fieldSizes: [
                .cardExpiration: PayabliTokenizationInputSize(height: 48),
                .cardCvv: PayabliTokenizationInputSize(height: 48)
            ]
        ),
        cardBrandIconPlacement: .trailing,
        errorMessagePlacement: .aboveSubmitButton
    ),
    onTokenized: { method in
        let storedMethodId = method.storedMethodId
        let fullResponse = method.apiResponse
        let resultText = fullResponse.responseData?.resultText
    },
    onError: { error in
        // Present an integration-specific error state.
    }
)
.payabliTokenizationStyle(
    PayabliTokenizationStyle(
        accentColor: .blue,
        input: PayabliTokenizationInputStyle(cornerRadius: 8),
        submitButton: PayabliTokenizationSubmitButtonStyle(cornerRadius: 8)
    )
)
```

Set `allowedMethods` to ` [.card]`, `[.ach]`, or `[.card, .ach]` to render
card-only, ACH-only, or dual-method forms.

Use `labelLayout: .external` for labels above inputs, or
`labelLayout: .placeholder` to put labels inside text inputs as placeholders.
Use `PayabliTokenizationLabels(submitButton:)` to override the submit button
text from the form configuration.

## SwiftUI Sheet

Use `.payabliTokenizationSheet(...)` when the host app wants the SDK-provided
bottom-sheet presentation around the same tokenization form:

```swift
Button("Add payment method") {
    isTokenizationPresented = true
}
.payabliTokenizationSheet(
    isPresented: $isTokenizationPresented,
    component: tokenization,
    configuration: PayabliTokenizationFormConfiguration(
        allowedMethods: [.card],
        labels: PayabliTokenizationLabels(
            title: "Add Card",
            submitButton: "Save Card"
        )
    ),
    sheetConfiguration: PayabliTokenizationSheetConfiguration(
        dismissButton: .back,
        dismissesOnTokenized: true,
        detents: [.medium, .large],
        sizesToContentWhenPossible: true,
        expandsToLargeWhenContentDoesNotFit: true
    ),
    style: PayabliTokenizationStyle(
        accentColor: .blue,
        input: PayabliTokenizationInputStyle(cornerRadius: 8),
        submitButton: PayabliTokenizationSubmitButtonStyle(cornerRadius: 8)
    ),
    onTokenized: { method in
        saveStoredMethodId(method.storedMethodId)
    },
    onError: { error in
        present(error)
    }
)
```

`PayabliTokenizationSheetConfiguration` controls sheet title override, optional
back or close dismiss button, whether the sheet dismisses after successful
tokenization, presentation detents, content-height sizing when the form fits on
screen, automatic expansion to `.large` when the form is too tall, drag
indicator visibility, content insets, and whether the form title/subtitle
should be moved into the sheet header.

## Form Configuration Reference

`PayabliTokenizationFormConfiguration` controls behavior and displayed fields.

| Property | Purpose |
|---|---|
| `allowedMethods` | Renders card, ACH, or both. |
| `defaultMethod` | Initial selected method when both are allowed. |
| `cardFieldOrder` | Visible card fields and order. Required card fields are appended if omitted. |
| `achFieldOrder` | Visible ACH fields and order. Required ACH fields are appended if omitted. |
| `hiddenValues` | Supplies optional values without rendering inputs. |
| `options` | API options applied to component submissions. |
| `labels` | Title, subtitle, submit label, and per-field label overrides. |
| `labelLayout` | `.external` labels above inputs or `.placeholder` labels inside inputs. |
| `formatting` | Card spacing, expiration separator, and ACH account masking. |
| `inputSizing` | Default and per-field width, height, and horizontal padding. |
| `cardBrandIconPlacement` | Card-number brand icon placement: `.leading`, `.trailing`, or `.hidden`. |
| `errorMessagePlacement` | Tokenization error placement: `.top` or `.aboveSubmitButton`. |

Supported visible fields:

- Card: `.cardholderName`, `.cardNumber`, `.cardExpiration`, `.cardCvv`,
  `.cardZip`
- ACH: `.achHolder`, `.achRouting`, `.achAccount`, `.achAccountType`,
  `.achHolderType`, `.achDevice`
- Shared/customer metadata: `.methodDescription`, `.firstName`, `.lastName`,
  `.customerNumber`, `.billingEmail`, `.billingZip`

Supported hidden values:

- `cardCvv`
- `achHolderType`
- `achSecCode` (defaults to `.web`)
- `achDevice`
- `methodDescription`
- `customerData`

Hidden values are used only when their matching field is not visible. Visible
field input wins over hidden/default data. Customer data from visible fields is
merged with `options.customerData` and `hiddenValues.customerData`.

The view preserves the configured field order. When adjacent, expiration/CVV
and first-name/last-name fields are rendered as paired inputs to save space.

## Configurable Endpoint Fields

`PayabliTokenizationOptions` supports the optional API fields outside the
required payment method values:

- Query flags: `achValidation`, `createAnonymous`, `forceCustomerCreation`,
  `temporary`
- Header: `idempotencyKey`
- Body: `customerData`, `vendorData`, `fallbackAuth`, `fallbackAuthAmount`,
  `methodDescription`, `source`, `subdomain`
- Validation policy: `PayabliTokenizationValidation`

Use `PayabliTokenizationFormConfiguration` for display concerns:

- `allowedMethods` and `defaultMethod`
- `cardFieldOrder` and `achFieldOrder`
- `hiddenValues`
- `labels`
- `labelLayout`
- `formatting`
- `inputSizing`
- `errorMessagePlacement`
- `cardBrandIconPlacement`

Use `PayabliTokenizationStyle` for visual concerns:

- `accentColor`
- Header, label, input, error, and submit button fonts and colors
- Input background, border, focused state, and corner radius
- Submit button enabled/disabled colors, height, padding, and corner radius
- Layout spacing for headers, fields, paired fields, and labels

Apply it with `.payabliTokenizationStyle(...)` to follow SwiftUI's standard
component styling pattern, or pass `style:` directly to `PayabliTokenizationView`
when a single instance needs an override.

## Style Samples

### Platform Default

Use this when the host app wants a native iOS form that follows the app accent
color and standard dynamic type.

```swift
let platformDefaultStyle = PayabliTokenizationStyle(
    accentColor: Color.accentColor,
    input: PayabliTokenizationInputStyle(
        backgroundColor: Color(uiColor: .secondarySystemBackground),
        borderColor: Color(uiColor: .separator).opacity(0.45),
        cornerRadius: 8
    ),
    submitButton: PayabliTokenizationSubmitButtonStyle(cornerRadius: 8)
)
```

### Compact Checkout

Use this when the form lives inside a checkout sheet or a dense account-settings
screen.

```swift
let compactCheckoutStyle = PayabliTokenizationStyle(
    accentColor: .green,
    title: PayabliTokenizationTextStyle(
        font: .headline,
        color: .primary
    ),
    subtitle: PayabliTokenizationTextStyle(
        font: .caption,
        color: .secondary
    ),
    label: PayabliTokenizationTextStyle(
        font: .caption.weight(.semibold),
        color: .secondary
    ),
    input: PayabliTokenizationInputStyle(
        font: .callout,
        backgroundColor: Color(uiColor: .systemBackground),
        borderColor: Color(uiColor: .separator),
        focusedBorderColor: .green,
        cornerRadius: 6
    ),
    submitButton: PayabliTokenizationSubmitButtonStyle(
        font: .callout.weight(.semibold),
        cornerRadius: 6,
        height: 46
    ),
    layout: PayabliTokenizationLayoutStyle(
        contentSpacing: 14,
        fieldGroupSpacing: 10,
        pairedFieldSpacing: 8,
        labelSpacing: 5
    )
)

let compactCheckoutSizing = PayabliTokenizationInputSizing(
    defaultSize: PayabliTokenizationInputSize(height: 46, horizontalPadding: 12),
    fieldSizes: [
        .cardExpiration: PayabliTokenizationInputSize(width: 132, height: 46),
        .cardCvv: PayabliTokenizationInputSize(width: 104, height: 46)
    ]
)
```

### High-Contrast Financial App

Use this when the host app needs stronger visual affordances and prominent
focused input states.

```swift
let highContrastStyle = PayabliTokenizationStyle(
    accentColor: .indigo,
    title: PayabliTokenizationTextStyle(
        font: .title3.weight(.bold),
        color: .primary
    ),
    label: PayabliTokenizationTextStyle(
        font: .footnote.weight(.bold),
        color: .primary
    ),
    input: PayabliTokenizationInputStyle(
        font: .body.weight(.medium),
        textColor: .primary,
        backgroundColor: Color(uiColor: .systemBackground),
        focusedBackgroundColor: Color.indigo.opacity(0.08),
        borderColor: Color(uiColor: .label).opacity(0.35),
        focusedBorderColor: .indigo,
        borderWidth: 1.25,
        focusedBorderWidth: 2,
        cornerRadius: 10,
        pickerIconColor: .indigo
    ),
    submitButton: PayabliTokenizationSubmitButtonStyle(
        backgroundColor: .indigo,
        foregroundColor: .white,
        disabledBackgroundColor: Color(uiColor: .systemGray4),
        cornerRadius: 10,
        height: 54
    ),
    error: PayabliTokenizationTextStyle(
        font: .footnote.weight(.semibold),
        color: .red
    )
)
```

## Error Handling

The component throws `PayabliTokenizationError` for tokenization-specific
failures:

- `.invalidInput` for SDK-side validation failures
- `.missingAccessToken` when the provider returns an empty token
- `.tokenizationFailed` when Payabli returns a decoded unsuccessful response

HTTP errors are mapped through Core's `mapPayabliHTTPError(response:)`, so host
apps should also handle the shared `PayabliError` family used by the rest of the
SDK.
