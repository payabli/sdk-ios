# PayabliSDKTokenization

`PayabliSDKTokenization` is an opt-in component for exchanging card PAN or
ACH data for a Payabli stored payment method ID via `POST /api/TokenStorage/add`.
It is not part of the `PayabliSDK` umbrella on this branch; apps link it
explicitly when they need card-not-present or ACH tokenization.

Detailed documentation:

- [`Documentation/TokenizationOverview.md`](../../Documentation/TokenizationOverview.md)
  documents every public feature, supported field, option, response property,
  and style hook.
- [`Documentation/TokenizationIntegrationGuide.md`](../../Documentation/TokenizationIntegrationGuide.md)
  gives native SwiftUI, Flutter, and MAUI integration paths.

## Security model

- The component never logs PAN, CVV, ACH account, routing number, or access
  tokens.
- Raw payment values are held in SwiftUI state only while the form is active
  and are cleared after a submit attempt.
- The endpoint uses `Authorization: Bearer <access token>`. Do not embed a
  long-lived private API token in a production app. Prefer an
  `accessTokenProvider` that asks your backend for an appropriately scoped token
  just before submission.
- Card numbers are Luhn-checked by default, ACH routing numbers use ABA checksum
  validation by default, and both checks can be disabled through
  `PayabliTokenizationValidation` only when an integration has a documented
  reason.

## Feature map

| Feature | API |
|---|---|
| Card tokenization | `PayabliTokenizationView` with `allowedMethods: [.card]` |
| ACH tokenization | `PayabliTokenizationView` with `allowedMethods: [.ach]` |
| Dual-method form | `PayabliTokenizationFormConfiguration(allowedMethods: [.card, .ach])` |
| Bottom-sheet presentation | `.payabliTokenizationSheet(...)` |
| Visible optional fields | `cardFieldOrder`, `achFieldOrder` |
| Card brand icon | `cardBrandIconPlacement: .leading`, `.trailing`, or `.hidden` |
| Hidden optional values | `PayabliTokenizationHiddenValues` |
| API options | `PayabliTokenizationOptions` |
| Redacted request/response diagnostics | `PayabliTokenizationDiagnostics.enabled { ... }` |
| Full response return | `PayabliTokenizedMethod.apiResponse` |
| External or placeholder labels | `PayabliTokenizationLabelLayout` |
| Error message placement | `errorMessagePlacement: .top` or `.aboveSubmitButton` |
| Submit button text | `PayabliTokenizationLabels(submitButton:)` |
| Per-input sizing | `PayabliTokenizationInputSizing` |
| Styling | `.payabliTokenizationStyle(...)` or `style:` |

## Maintainer notes

This README is the internal entry point for SDK maintainers. Use the public
documentation above for integrator-facing copy.

File ownership:

- `PayabliTokenization.swift` owns the public component facade and dependency
  injection points.
- `TokenStorageClient.swift` owns `POST /api/TokenStorage/add`, bearer
  authorization, query serialization, response decoding, and diagnostics
  hooks.
- `PayabliTokenizationTypes.swift` owns public DTOs, API response models,
  validation helpers, and local error types.
- `PayabliTokenizationViewModel.swift` owns transient form state, validation,
  payload assembly, and field clearing after submission.
- `PayabliTokenizationView.swift` and `PayabliTokenizationSheet.swift` own
  SwiftUI rendering only.
- `PayabliTokenization+ObjC.swift` is the bridge surface used by MAUI and any
  Objective-C-compatible host. Keep its selector shape in sync with
  `Bridges/MAUI/PayabliBinding.cs` whenever parameters change.
- `Resources/PayabliBrandAssets.xcassets` contains the Payabli-approved card
  brand marks used by `PayabliTokenizationCardBrand`.

Maintenance checklist:

- Run the focused test target after code or docs examples move:
  `xcodebuild test -scheme PayabliSDK-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' -only-testing:PayabliSDKTokenizationTests`.
- Build the QA sample when view, sheet, diagnostics, secrets, or local token
  server behavior changes.
- Keep SwiftUI, Flutter, and MAUI examples aligned on the Bearer token flow.
  `requestToken` is intentionally not part of this component.
- Keep redaction tests current when adding request fields. Diagnostics must
  not expose bearer tokens, PAN, CVV, ACH account/routing values,
  customer/cardholder PII, or stored-method identifiers.
- If the public product changes, update `Package.swift`, release scripts, and
  public docs together so generated XCFramework artifacts and checksums remain
  coherent.

## SwiftUI component

```swift
PayabliTokenizationView(
    component: tokenization,
    configuration: PayabliTokenizationFormConfiguration(
        allowedMethods: [.card, .ach],
        cardFieldOrder: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip],
        achFieldOrder: [.achHolder, .achRouting, .achAccount, .achAccountType],
        hiddenValues: PayabliTokenizationHiddenValues(
            achHolderType: .personal,
            achSecCode: .web,
            methodDescription: "Primary payment method"
        ),
        options: PayabliTokenizationOptions(
            achValidation: true,
            createAnonymous: false,
            forceCustomerCreation: true,
            temporary: false
        ),
        labels: PayabliTokenizationLabels(
            title: "Payment Method",
            subtitle: "Save a payment method for future transactions.",
            submitButton: "Save Method"
        ),
        labelLayout: .external,
        formatting: PayabliTokenizationFormatting(insertsCardNumberSpaces: true),
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
        print(method.storedMethodId ?? "")
        print(method.apiResponse.responseText)
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

Use the sheet modifier when the host app wants the SDK-provided bottom-sheet
experience instead of embedding the form inline:

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
        sizesToContentWhenPossible: true,
        expandsToLargeWhenContentDoesNotFit: true
    ),
    onTokenized: { method in
        print(method.storedMethodId ?? "")
    }
)
```

The sheet sizes itself to the rendered form height when it fits on screen, so
fields and the submit button stay grouped together near the sheet edge. If the
rendered form is taller than the available sheet height and `.large` is
available, the sheet opens to `.large` and remains scrollable.

`PayabliTokenizationOptions` exposes the configurable fields outside the
required payment-method values: query flags, idempotency key, customer data,
vendor data, fallback auth, method description, source, and subdomain.
`PayabliTokenizationFormConfiguration` controls whether the form is card-only,
ACH-only, or dual-method, which optional fields are visible, hidden field
values, submit button text, label layout, formatting, and per-field input
sizing. The default submit button text is "Add Payment Method". Card ZIP is
always required and cannot be supplied as a hidden value.
ACH SEC Code is sent from `hiddenValues.achSecCode` and defaults to `.web`.
Tokenization API failures are decoded from `isSuccess: false` responses before
generic HTTP mapping; the form renders the user-facing message at the configured
`errorMessagePlacement`.
`PayabliTokenizationStyle` controls visual styling using the same SwiftUI
modifier shape as `buttonStyle` and `textFieldStyle`.

For complete style samples, including platform default, compact checkout, and
high-contrast configurations, see the overview documentation.

## Development Diagnostics

Request/response diagnostics are off by default. Enable them only in local or
QA builds when you need to inspect the final URL, query string, headers, and
JSON payloads sent by tokenization:

```swift
let tokenization = PayabliTokenization(
    entryPoint: Secrets.entryPoint,
    environment: .sandbox,
    accessTokenProvider: { try await Secrets.fetchTokenizationAccessToken() },
    diagnostics: .enabled { entry in
        print("[\(entry.phase.rawValue)] \(entry.method) \(entry.url)")
        print(entry.headers)
        print(entry.body ?? "")
    }
)
```

The handler receives `PayabliTokenizationDiagnosticEntry` values for request,
response, and transport-failure phases. Headers and JSON bodies are redacted
before they reach the handler: bearer tokens, PAN, CVV, ACH account/routing
values, cardholder/customer PII, and stored-method identifiers are replaced
with `[REDACTED]`.
