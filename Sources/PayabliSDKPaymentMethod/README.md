# PayabliSDKPaymentMethod

`PayabliSDKPaymentMethod` is an opt-in component for exchanging card PAN or
ACH data for a Payabli stored payment method ID via `POST /api/TokenStorage/add`.
It is not part of the `PayabliSDK` umbrella on this branch; apps link it
explicitly when they need card-not-present or ACH payment method.

Detailed documentation:

- [`Documentation/PaymentMethodOverview.md`](../../Documentation/PaymentMethodOverview.md)
  documents every public feature, supported field, option, response property,
  and style hook.
- [`Documentation/PaymentMethodIntegrationGuide.md`](../../Documentation/PaymentMethodIntegrationGuide.md)
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
  `PayabliPaymentMethodValidation` only when an integration has a documented
  reason.

## Feature map

| Feature | API |
|---|---|
| Card payment method | `PayabliPaymentMethodView` with `allowedMethods: [.card]` |
| ACH payment method | `PayabliPaymentMethodView` with `allowedMethods: [.ach]` |
| Dual-method form | `PayabliPaymentMethodFormConfiguration(allowedMethods: [.card, .ach])` |
| Bottom-sheet presentation | `.payabliPaymentMethodSheet(...)` |
| Visible optional fields | `cardFieldOrder`, `achFieldOrder` |
| Card brand icon | `cardBrandIconPlacement: .leading`, `.trailing`, or `.hidden` |
| Hidden optional values | `PayabliPaymentMethodHiddenValues` |
| API options | `PayabliPaymentMethodOptions` |
| Redacted request/response diagnostics | `PayabliPaymentMethodDiagnostics.enabled { ... }` |
| Full response return | `PayabliStoredPaymentMethod.apiResponse` |
| External or placeholder labels | `PayabliPaymentMethodLabelLayout` |
| Error message placement | `errorMessagePlacement: .top` or `.aboveSubmitButton` |
| Submit button text | `PayabliPaymentMethodLabels(submitButton:)` |
| Per-input sizing | `PayabliPaymentMethodInputSizing` |
| Styling | `.payabliPaymentMethodStyle(...)` or `style:` |

## Maintainer notes

This README is the internal entry point for SDK maintainers. Use the public
documentation above for integrator-facing copy.

File ownership:

- `PayabliPaymentMethod.swift` owns the public component facade and dependency
  injection points.
- `TokenStorageClient.swift` owns `POST /api/TokenStorage/add`, bearer
  authorization, query serialization, response decoding, and diagnostics
  hooks.
- `PayabliPaymentMethodTypes.swift` owns public DTOs, API response models,
  validation helpers, and local error types.
- `PayabliPaymentMethodViewModel.swift` owns transient form state, validation,
  payload assembly, and field clearing after submission.
- `PayabliPaymentMethodView.swift` and `PayabliPaymentMethodSheet.swift` own
  SwiftUI rendering only.
- `PayabliPaymentMethod+ObjC.swift` is the bridge surface used by MAUI and any
  Objective-C-compatible host. Keep its selector shape in sync with
  `Bridges/MAUI/PayabliBinding.cs` whenever parameters change.
- `Resources/PayabliBrandAssets.xcassets` contains the Payabli-approved card
  brand marks used by `PayabliPaymentMethodCardBrand`.

Maintenance checklist:

- Run the focused test target after code or docs examples move:
  `xcodebuild test -scheme PayabliSDK-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' -only-testing:PayabliSDKPaymentMethodTests`.
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
PayabliPaymentMethodView(
    component: paymentMethod,
    configuration: PayabliPaymentMethodFormConfiguration(
        allowedMethods: [.card, .ach],
        cardFieldOrder: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip],
        achFieldOrder: [.achHolder, .achRouting, .achAccount, .achAccountType],
        hiddenValues: PayabliPaymentMethodHiddenValues(
            achHolderType: .personal,
            achSecCode: .web,
            methodDescription: "Primary payment method"
        ),
        options: PayabliPaymentMethodOptions(
            achValidation: true,
            createAnonymous: false,
            forceCustomerCreation: true,
            temporary: false
        ),
        labels: PayabliPaymentMethodLabels(
            title: "Payment Method",
            subtitle: "Save a payment method for future transactions.",
            submitButton: "Save Method"
        ),
        labelLayout: .external,
        formatting: PayabliPaymentMethodFormatting(insertsCardNumberSpaces: true),
        inputSizing: PayabliPaymentMethodInputSizing(
            defaultSize: PayabliPaymentMethodInputSize(height: 52),
            fieldSizes: [
                .cardExpiration: PayabliPaymentMethodInputSize(height: 48),
                .cardCvv: PayabliPaymentMethodInputSize(height: 48)
            ]
        ),
        cardBrandIconPlacement: .trailing,
        errorMessagePlacement: .aboveSubmitButton
    ),
    onPaymentMethodAdded: { method in
        print(method.storedMethodId ?? "")
        print(method.apiResponse.responseText)
    }
)
.payabliPaymentMethodStyle(
    PayabliPaymentMethodStyle(
        accentColor: .blue,
        input: PayabliPaymentMethodInputStyle(cornerRadius: 8),
        submitButton: PayabliPaymentMethodSubmitButtonStyle(cornerRadius: 8)
    )
)
```

Use the sheet modifier when the host app wants the SDK-provided bottom-sheet
experience instead of embedding the form inline:

```swift
Button("Add payment method") {
    isPaymentMethodPresented = true
}
.payabliPaymentMethodSheet(
    isPresented: $isPaymentMethodPresented,
    component: paymentMethod,
    configuration: PayabliPaymentMethodFormConfiguration(
        allowedMethods: [.card],
        labels: PayabliPaymentMethodLabels(
            title: "Add Card",
            submitButton: "Save Card"
        )
    ),
    sheetConfiguration: PayabliPaymentMethodSheetConfiguration(
        dismissButton: .back,
        sizesToContentWhenPossible: true,
        expandsToLargeWhenContentDoesNotFit: true
    ),
    onPaymentMethodAdded: { method in
        print(method.storedMethodId ?? "")
    }
)
```

The sheet sizes itself to the rendered form height when it fits on screen, so
fields and the submit button stay grouped together near the sheet edge. If the
rendered form is taller than the available sheet height and `.large` is
available, the sheet opens to `.large` and remains scrollable.

`PayabliPaymentMethodOptions` exposes the configurable fields outside the
required payment-method values: query flags, idempotency key, customer data,
vendor data, fallback auth, method description, source, and subdomain.
`PayabliPaymentMethodFormConfiguration` controls whether the form is card-only,
ACH-only, or dual-method, which optional fields are visible, hidden field
values, submit button text, label layout, formatting, per-field input sizing,
and additional required optional fields. The default submit button text is
"Add Payment Method". Card CVV and ZIP are always required and cannot be
supplied as hidden values.
ACH SEC Code is sent from `hiddenValues.achSecCode` and defaults to `.web`.
Payment Method API failures are decoded from `isSuccess: false` responses before
generic HTTP mapping; the form renders the user-facing message at the configured
`errorMessagePlacement`.
`PayabliPaymentMethodStyle` controls visual styling using the same SwiftUI
modifier shape as `buttonStyle` and `textFieldStyle`.

For complete style samples, including platform default, compact checkout, and
high-contrast configurations, see the overview documentation.

## Development Diagnostics

Request/response diagnostics are off by default. Enable them only in local or
QA builds when you need to inspect the final URL, query string, headers, and
JSON payloads sent by payment method:

```swift
let paymentMethod = PayabliPaymentMethod(
    entryPoint: Secrets.entryPoint,
    environment: .sandbox,
    accessTokenProvider: { try await Secrets.fetchPaymentMethodAccessToken() },
    diagnostics: .enabled { entry in
        print("[\(entry.phase.rawValue)] \(entry.method) \(entry.url)")
        print(entry.headers)
        print(entry.body ?? "")
    }
)
```

The handler receives `PayabliPaymentMethodDiagnosticEntry` values for request,
response, and transport-failure phases. Headers and JSON bodies are redacted
before they reach the handler: bearer tokens, PAN, CVV, ACH account/routing
values, cardholder/customer PII, and stored-method identifiers are replaced
with `[REDACTED]`.

The QA sample app also includes local success and failure mock responses for
UI/UX testing. Configure `paymentMethodMockSuccessEnabled` or
`paymentMethodMockFailureEnabled` in `Example/PayabliDemo/Secrets.swift`;
the exact response bodies are documented in the sample app README and the
payment method integration guide.
