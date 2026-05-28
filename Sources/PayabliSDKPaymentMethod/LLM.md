# PayabliSDKPaymentMethod LLM Reference

This file is the compact context pack for answering product, developer, and
solution-engineering questions about the Payabli iOS Payment Method component.
It describes the current implementation in this folder. Prefer this file when
an LLM needs a fast, accurate answer; use `README.md` and the files listed at
the end for deeper implementation details.

## Product Persona

### What problem does this component solve?

`PayabliSDKPaymentMethod` lets an iOS app collect card or ACH payment method
details and exchange them for a Payabli stored payment method through:

```text
POST /api/TokenStorage/add
```

The app receives a stored method identifier, not reusable raw payment details.
That stored method can then be used by the integrator for future Payabli
payment flows according to the integrator's backend and product model.

### Why does it exist?

The component gives Payabli integrators a reusable native iOS experience for
adding a payment method without forcing every host app to rebuild sensitive
card and ACH collection, validation, request construction, redaction, and
error handling from scratch.

### Core product values

- Safer collection: raw PAN, CVV, ACH account number, and routing number stay
  inside SDK-owned form state during entry. Sensitive values are cleared after
  success; card CVV is also cleared after a failed card submit.
- Backend-owned credentials: the mobile app supplies a short-lived Bearer token
  through `accessTokenProvider`; it must not ship a private Payabli
  `clientSecret`.
- Native UX: the SDK provides an inline SwiftUI component and an SDK-owned
  bottom-sheet presentation.
- Configurable integration: the host app controls method coverage, field order,
  labels, styles, visible optional fields, required optional fields, hidden
  values, query flags, source tags, and diagnostics.
- QA visibility: development diagnostics log the final URL, query string,
  headers, request body, and response body after sensitive values are redacted.

### Current capabilities

- Card payment method collection.
- ACH payment method collection for US banks.
- Inline SwiftUI form: `PayabliPaymentMethodView`.
- SDK-provided sheet wrapper: `.payabliPaymentMethodSheet(...)`.
- Card-only, ACH-only, or dual card/ACH segmented form.
- Card brand detection while typing.
- Payabli-approved card brand assets for Visa, Mastercard, American Express,
  and Discover.
- Configurable card brand placement: `.leading`, `.trailing`, or `.hidden`.
- Luhn validation for card number by default.
- Red card-number state with the text `Invalid Card Number` as the user types
  once enough digits exist and the Luhn check fails.
- Month/year expiration picker using side-by-side wheel pickers.
- ACH routing ABA checksum validation by default.
- Hidden ACH SEC Code value, defaulting to `WEB`.
- Required CVV and ZIP for card submissions.
- Optional visible metadata fields, with selected optional fields configurable
  as required.
- Error message rendering at `.top` or `.aboveSubmitButton`.
- Local QA success and failure mocks in the sample app.
- Redacted diagnostics for development and QA.
- Objective-C-compatible wrapper for bridge layers such as MAUI.
- Flutter and MAUI integration guidance in the repo-level documentation.

### Current boundaries

- This component saves a payment method. It does not charge a payment.
- This component uses the Bearer token approach only. It intentionally does not
  use `requestToken`.
- This component does not create a partner backend. The integrator must provide
  a backend endpoint that exchanges Payabli server-side credentials for an
  access token.
- This component must not receive or store a long-lived Payabli private token
  in production mobile app code.
- The ACH form is for US ACH bank accounts. It does not support international
  bank rails.
- Billing email is not a default field. It can be added as an optional visible
  customer field and can be made required if an integration needs it.

## Developer Persona

### Package and module

- Swift package product: `PayabliSDKPaymentMethod`
- Main module: `PayabliSDKPaymentMethod`
- Depends on: `PayabliSDKCore`
- Not part of the `PayabliSDK` umbrella on this branch; host apps link it
  explicitly.

Import:

```swift
import PayabliSDKCore
import PayabliSDKPaymentMethod
```

### Public component facade

Primary type:

```swift
@MainActor
public final class PayabliPaymentMethod: NSObject, ObservableObject, PayabliComponent
```

Component metadata:

| Property | Value |
|---|---|
| `componentId` | `paymentMethod` |
| `sessionTier` | `.tier1Transactional` |
| `requiredPermissions` | `["tokenstorage:add"]` |

Production initializer:

```swift
PayabliPaymentMethod(
    entryPoint: String,
    environment: PayabliEnvironment,
    accessTokenProvider: @escaping PayabliPaymentMethodAccessTokenProvider,
    transport: (any PayabliTransport)? = nil,
    diagnostics: PayabliPaymentMethodDiagnostics = .disabled
)
```

Conveniences:

- `init(config:accessTokenProvider:transport:diagnostics:)`
- `init(accessToken:entryPoint:environment:transport:diagnostics:)` for tests,
  demos, or ephemeral tokens only.
- `configure(config:)` to repoint the component at another entry point and
  environment.

Submission APIs:

- `addPaymentMethod(_:options:)`
- `addCard(_:options:)`
- `addACH(_:options:)`

Published state:

- `isSubmitting`
- `lastStoredPaymentMethod`

### Authentication integration

Every submit calls the host-provided `accessTokenProvider` immediately before
building the request. The provider must return the Bearer access token string.

The SDK then sends:

```text
Authorization: Bearer <access token>
```

The server-side Payabli token exchange is not performed by the SDK. A partner
backend can call the environment-specific server-side token endpoint:

```bash
curl --location 'https://api-sandbox.payabli.com/api/v2/token/serverside' \
  --header 'Content-Type: application/json' \
  --data '{
    "clientId": "{clientId}",
    "clientSecret": "{clientSecret}"
  }'
```

QA uses:

```text
https://api-qa.payabli.com/api/v2/token/serverside
```

The Payabli response is:

```json
{
  "token_type": "Bearer",
  "access_token": "{access_token}",
  "expires_in": 3600
}
```

The mobile-facing backend can return either `accessToken` or `access_token`;
the sample app accepts both.

### Endpoint request

The component posts to:

```text
POST /api/TokenStorage/add
```

Request construction lives in `TokenStorageClient.swift`.

Headers:

| Header | Source |
|---|---|
| `Authorization` | `Bearer <accessTokenProvider result>` |
| `idempotencyKey` | `PayabliPaymentMethodOptions.idempotencyKey`, when non-empty |

Query parameters:

| Query parameter | Source | Default behavior |
|---|---|---|
| `achValidation` | `PayabliPaymentMethodOptions.achValidation` | Omitted when `nil` |
| `createAnonymous` | `PayabliPaymentMethodOptions.createAnonymous` | Omitted when `nil` |
| `forceCustomerCreation` | `PayabliPaymentMethodOptions.forceCustomerCreation` | Omitted when `nil` |
| `temporary` | `PayabliPaymentMethodOptions.temporary` | Omitted when `nil` |

Recommended QA/customer-owned reusable method options:

```swift
PayabliPaymentMethodOptions(
    achValidation: true,
    createAnonymous: false,
    forceCustomerCreation: true,
    temporary: false,
    source: "ios-tokenization-qa"
)
```

Body envelope:

| JSON field | Source |
|---|---|
| `customerData` | `options.customerData`, hidden customer data, and visible customer fields |
| `entryPoint` | `PayabliPaymentMethod.entryPoint` |
| `fallbackAuth` | `options.fallbackAuth` |
| `fallbackAuthAmount` | `options.fallbackAuthAmount` |
| `methodDescription` | `options.methodDescription`, hidden value, or visible field |
| `paymentMethod` | Encoded card or ACH method |
| `vendorData` | `options.vendorData` |
| `source` | `options.source` |
| `subdomain` | `options.subdomain` |

### Card field mapping

Card input type:

```swift
PayabliCardPaymentMethodData(
    cardNumber: String,
    expiration: String,
    cardholderName: String,
    cvv: String? = nil,
    billingZip: String
)
```

Encoded `paymentMethod` mapping:

| JSON field | Value |
|---|---|
| `method` | `"card"` |
| `cardnumber` | Digits only from `cardNumber` |
| `cardexp` | Normalized `MM/YY` |
| `cardHolder` | Trimmed `cardholderName` |
| `cardcvv` | Digits only from `cvv` |
| `cardzip` | Trimmed `billingZip` |

Card validation and limits:

| Field | Requirement |
|---|---|
| Name on card | Required, 60 characters max |
| Card number | Required, 12 to 19 digits, capped at 19 digits in UI |
| Card number Luhn | Required by default through `PayabliPaymentMethodValidation` |
| Expiration | Required, accepts `MMYY` or `MM/YY`, normalizes to `MM/YY` |
| Expiration month | Must be `01` through `12` |
| CVV | Required, 3 to 4 digits, capped at 4 digits in UI |
| ZIP/postal code | Required, 12 characters max |

Card UX:

- Default card field order is name on card, card number, expiration, CVV, ZIP.
- Card number uses a UIKit-backed text field to enforce entry caps during
  typing.
- Card number spaces are inserted by default in groups of four.
- Card brand icon placement defaults to trailing.
- `brand-visa`, `brand-mastercard`, `brand-amex`, and `brand-discover` are
  loaded from `Resources/PayabliBrandAssets.xcassets`.
- Diners Club, JCB, UnionPay, and unknown can be detected but currently render
  the generic card icon because no Payabli brand asset is included for them.

### ACH field mapping

ACH input type:

```swift
PayabliACHPaymentMethodData(
    accountNumber: String,
    accountType: PayabliACHAccountType,
    holderName: String,
    routingNumber: String,
    secCode: PayabliACHSecCode? = .web,
    holderType: PayabliACHHolderType? = nil,
    device: String? = nil
)
```

Encoded `paymentMethod` mapping:

| JSON field | Value |
|---|---|
| `method` | `"ach"` |
| `achAccount` | Digits only from `accountNumber` |
| `achAccountType` | `"Checking"` or `"Savings"` |
| `achHolder` | Trimmed `holderName` |
| `achRouting` | Digits only from `routingNumber` |
| `achCode` | SEC Code raw value, defaulting to `"WEB"` |
| `achHolderType` | `"personal"` or `"business"`, when present |
| `device` | Trimmed device value, when present |

ACH validation and limits:

| Field | Requirement |
|---|---|
| Account holder | Required, 60 characters max |
| Account holder characters | Letters, digits, spaces, period, apostrophe, hyphen |
| Routing number | Required, exactly 9 digits |
| Routing checksum | ABA checksum required by default |
| Account number | Required, 4 to 17 digits |
| Account type | Required, `.checking` or `.savings` |
| SEC Code | Hidden request value only; defaults to `.web` |

ACH SEC Code values:

| Swift case | API value |
|---|---|
| `.ppd` | `PPD` |
| `.web` | `WEB` |
| `.tel` | `TEL` |
| `.ccd` | `CCD` |
| `.boc` | `BOC` |

### Form configuration defaults

`PayabliPaymentMethodFormConfiguration` controls rendered fields and form
behavior.

| Property | Default |
|---|---|
| `allowedMethods` | `[.card, .ach]` |
| `defaultMethod` | `.card` |
| `cardFieldOrder` | `[.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]` |
| `achFieldOrder` | `[.achHolder, .achRouting, .achAccount, .achAccountType, .achHolderType]` |
| `hiddenValues` | `achSecCode: .web`, all others nil |
| `options` | All API option fields nil, validation default |
| `labels.title` | `"Save Payment Method"` |
| `labels.submitButton` | `"Add Payment Method"` |
| `labelLayout` | `.external` |
| `formatting.insertsCardNumberSpaces` | `true` |
| `formatting.expirationSeparator` | `"/"` |
| `formatting.masksACHAccountEntry` | `true` |
| `inputSizing.defaultSize` | width nil, height 52, horizontal padding 14 |
| `cardBrandIconPlacement` | `.trailing` |
| `errorMessagePlacement` | `.aboveSubmitButton` |
| `requiredFields` | `[]` |

Supported visible fields:

| Category | Fields |
|---|---|
| Card | `.cardholderName`, `.cardNumber`, `.cardExpiration`, `.cardCvv`, `.cardZip` |
| ACH | `.achHolder`, `.achRouting`, `.achAccount`, `.achAccountType`, `.achHolderType`, `.achDevice` |
| Customer/shared | `.methodDescription`, `.firstName`, `.lastName`, `.customerNumber`, `.billingEmail`, `.billingZip` |

Special field behavior:

- `.achSecCode` is filtered out of visible ACH fields and must be supplied as a
  hidden value.
- Required card fields are appended to `cardFieldOrder` if omitted.
- Required ACH fields are appended to `achFieldOrder` if omitted.
- `requiredFields` can require optional visible fields such as
  `.billingEmail`, `.methodDescription`, or `.achDevice`.
- `requiredFields` cannot make core API-required fields optional.
- `requiredFields` ignores `.achSecCode` because SEC Code is hidden-only.
- Adjacent expiration/CVV fields render as paired inputs.
- Adjacent first-name/last-name fields render as paired inputs.

### Hidden values

Use `PayabliPaymentMethodHiddenValues` when the integrator needs to send values
without rendering inputs.

```swift
PayabliPaymentMethodHiddenValues(
    achHolderType: .personal,
    achSecCode: .web,
    achDevice: nil,
    methodDescription: "Primary payment method",
    customerData: PayabliPaymentMethodCustomerData(customerNumber: "customer-123")
)
```

Hidden values are used when the matching field is not visible. Visible field
input wins over hidden/default data. Customer data from visible fields is
merged with `options.customerData` and `hiddenValues.customerData`.

### Styling hooks

Use `PayabliPaymentMethodStyle` directly on a view or through the environment:

```swift
.payabliPaymentMethodStyle(PayabliPaymentMethodStyle(...))
```

Style controls:

- Accent color.
- Title, subtitle, label, input, error, and submit button text styles.
- Input background, focused background, border, focused border, border widths,
  corner radius, text color, and picker icon color.
- Submit button enabled and disabled colors, height, padding, font, and corner
  radius.
- Layout spacing.

### Sheet configuration

The SDK-owned sheet is exposed as:

```swift
.payabliPaymentMethodSheet(...)
```

`PayabliPaymentMethodSheetConfiguration` defaults:

| Property | Default |
|---|---|
| `dismissButton` | `.close` |
| `dismissesOnSuccess` | `true` |
| `detents` | `[.medium, .large]` |
| `dragIndicatorVisibility` | `.visible` |
| `contentInsets` | top 20, leading 20, bottom 24, trailing 20 |
| `movesFormHeaderToSheetHeader` | `true` |
| `sizesToContentWhenPossible` | `true` |
| `expandsToLargeWhenContentDoesNotFit` | `true` |

Sheet behavior:

- Uses the same `PayabliPaymentMethodView` internally.
- Moves title/subtitle into the sheet header by default to avoid duplicate
  headers.
- Sizes to rendered content height when it fits on screen.
- Opens to `.large` when content is taller than the available sheet height and
  `.large` is available.
- Disables form animations inside the sheet to avoid visible flicker during
  validation and method changes.

### Response mapping

The endpoint response is decoded as:

```swift
PayabliPaymentMethodAPIResponse(
    isSuccess: Bool?,
    responseText: String,
    responseCode: Int?,
    responseData: PayabliPaymentMethodAPIResponseData?
)
```

Success is accepted when either:

- `isSuccess == true`, or
- `responseData.resultCode == 1`

Returned SDK model:

| `PayabliStoredPaymentMethod` property | Source |
|---|---|
| `storedMethodId` | `responseData.referenceId` |
| `methodReferenceId` | `responseData.methodReferenceId` |
| `resultCode` | `responseData.resultCode` |
| `resultText` | `responseData.resultText` |
| `customerId` | `responseData.customerId` |
| `responseText` | top-level `responseText` |
| `apiResponse` | full decoded API response |

Integrators should store only `storedMethodId` and safe metadata. Do not store
PAN, CVV, ACH account number, routing number, or access tokens.

### Error handling

Payment-method-specific error type:

```swift
public enum PayabliPaymentMethodError: PayabliError {
    case invalidInput(String)
    case missingAccessToken
    case saveFailed(PayabliPaymentMethodFailure)
}
```

Failure response handling:

- If the endpoint returns a decoded body with `isSuccess == false`, the SDK
  throws `.saveFailed(...)` before generic HTTP mapping.
- The only guaranteed failure fields across 4XX/5XX are:

```json
{
  "isSuccess": false,
  "responseText": "{responseText}"
}
```

- When present, `responseData.explanation` is preferred for the user-facing
  reason.
- Then `responseData.resultText`.
- For 500+ responses without a better message, the SDK uses
  `"Unable to save payment method right now. Please try again."`
- Otherwise the SDK uses top-level `responseText`.
- `responseData.todoAction` is exposed as detail and appended by the form when
  distinct from the reason.

The SwiftUI view renders `viewModel.errorMessage` at the configured
`errorMessagePlacement`.

### Diagnostics

Diagnostics are off by default:

```swift
diagnostics: .disabled
```

Enable only in local or QA builds:

```swift
let component = PayabliPaymentMethod(
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

Diagnostic entry fields:

- `phase`: `.request`, `.response`, or `.failure`
- `timestamp`
- `method`
- `url`, including query parameters
- `statusCode`
- redacted `headers`
- redacted `body`
- `durationMilliseconds`
- `errorDescription`

Redaction covers bearer tokens, request tokens, access tokens, client secrets,
PAN, CVV, expiration, ZIP, ACH account/routing/holder fields, stored method
identifiers, customer identifiers, names, emails, phones, and addresses.

### Local QA mocks

The sample app can bypass sandbox for UI/UX QA. In
`Example/PayabliDemo/Secrets.swift`:

```swift
static let paymentMethodMockSuccessEnabled = true
static let paymentMethodMockFailureEnabled = false
```

or:

```swift
static let paymentMethodMockSuccessEnabled = false
static let paymentMethodMockFailureEnabled = true
```

If both are enabled, failure wins.

Success mock:

```json
{
  "isSuccess": true,
  "responseText": "Success",
  "responseData": {
    "referenceId": "qa-mock-stored-method",
    "resultCode": 1,
    "resultText": "Approved",
    "methodReferenceId": "qa-mock-method-reference",
    "customerId": 123456789
  }
}
```

Failure mock:

```json
{
  "isSuccess": false,
  "responseText": "Error",
  "responseCode": 6000,
  "responseData": {
    "explanation": "Invalid Card",
    "todoAction": "Please check your card details and try again."
  }
}
```

### Important source files

| File | Ownership |
|---|---|
| `PayabliPaymentMethod.swift` | Public component facade and dependency injection |
| `TokenStorageClient.swift` | `POST /api/TokenStorage/add`, Bearer auth, query serialization, response decoding |
| `PayabliPaymentMethodTypes.swift` | Public DTOs, options, API response models, validation, errors |
| `PayabliPaymentMethodViewModel.swift` | Form state, validation, payload assembly, field clearing |
| `PayabliPaymentMethodView.swift` | Inline SwiftUI form, fields, labels, validation UI |
| `PayabliPaymentMethodSheet.swift` | SDK-owned sheet presentation |
| `PayabliPaymentMethodStyle.swift` | Style API and environment modifier |
| `PayabliPaymentMethodDiagnostics.swift` | Redacted diagnostics |
| `PayabliPaymentMethodUIKitTextField.swift` | UIKit text field bridge for strict input caps |
| `PayabliPaymentMethod+ObjC.swift` | Objective-C-compatible bridge surface |

## Solution Engineer Persona

### Integration path in simple steps

1. Add `PayabliSDKPaymentMethod` to the host app target.
2. Build or configure a partner backend endpoint that returns a Payabli Bearer
   `access_token` for the mobile app.
3. Create a `PayabliPaymentMethod` instance with the Payabli entry point,
   environment, and `accessTokenProvider`.
4. Choose the presentation:
   - Inline form with `PayabliPaymentMethodView`.
   - SDK-owned bottom sheet with `.payabliPaymentMethodSheet(...)`.
5. Configure card-only, ACH-only, or both methods.
6. Set customer behavior with options:
   - `createAnonymous: false`
   - `forceCustomerCreation: true`
   - `temporary: false`
7. Configure visible fields, hidden values, labels, style, and error placement.
8. On success, store `method.storedMethodId` and any safe metadata.
9. On failure, show the SDK-rendered message or use `onError` for app-level
   handling.
10. Enable redacted diagnostics only for local or QA validation.

### Minimal inline SwiftUI example

```swift
import SwiftUI
import PayabliSDKCore
import PayabliSDKPaymentMethod

struct AddPaymentMethodScreen: View {
    @StateObject private var paymentMethod = PayabliPaymentMethod(
        entryPoint: "<PAYABLI_ENTRY_POINT>",
        environment: .sandbox,
        accessTokenProvider: {
            try await Backend.shared.fetchPaymentMethodAccessToken()
        }
    )

    var body: some View {
        PayabliPaymentMethodView(
            component: paymentMethod,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.card, .ach],
                defaultMethod: .card,
                options: PayabliPaymentMethodOptions(
                    achValidation: true,
                    createAnonymous: false,
                    forceCustomerCreation: true,
                    temporary: false,
                    source: "ios-app"
                ),
                errorMessagePlacement: .aboveSubmitButton
            ),
            onPaymentMethodAdded: { method in
                saveStoredMethodId(method.storedMethodId)
            },
            onError: { error in
                present(error)
            }
        )
        .padding()
    }
}
```

### Minimal sheet example

```swift
struct CheckoutScreen: View {
    @State private var isPresented = false
    @StateObject private var paymentMethod = PayabliPaymentMethod(
        entryPoint: "<PAYABLI_ENTRY_POINT>",
        environment: .sandbox,
        accessTokenProvider: {
            try await Backend.shared.fetchPaymentMethodAccessToken()
        }
    )

    var body: some View {
        Button("Add payment method") {
            isPresented = true
        }
        .payabliPaymentMethodSheet(
            isPresented: $isPresented,
            component: paymentMethod,
            configuration: PayabliPaymentMethodFormConfiguration(
                allowedMethods: [.card],
                labels: PayabliPaymentMethodLabels(
                    title: "Add Card",
                    submitButton: "Add Payment Method"
                ),
                options: PayabliPaymentMethodOptions(
                    createAnonymous: false,
                    forceCustomerCreation: true,
                    temporary: false,
                    source: "ios-app"
                )
            ),
            sheetConfiguration: PayabliPaymentMethodSheetConfiguration(
                dismissButton: .back,
                dismissesOnSuccess: true,
                sizesToContentWhenPossible: true,
                expandsToLargeWhenContentDoesNotFit: true
            ),
            onPaymentMethodAdded: { method in
                saveStoredMethodId(method.storedMethodId)
            },
            onError: { error in
                present(error)
            }
        )
    }
}
```

### Common configuration recipes

Card only:

```swift
PayabliPaymentMethodFormConfiguration(
    allowedMethods: [.card]
)
```

ACH only:

```swift
PayabliPaymentMethodFormConfiguration(
    allowedMethods: [.ach],
    defaultMethod: .ach,
    hiddenValues: PayabliPaymentMethodHiddenValues(
        achHolderType: .personal,
        achSecCode: .web
    ),
    options: PayabliPaymentMethodOptions(
        achValidation: true,
        createAnonymous: false,
        forceCustomerCreation: true,
        temporary: false
    )
)
```

Require optional visible fields:

```swift
PayabliPaymentMethodFormConfiguration(
    requiredFields: [.billingEmail, .methodDescription]
)
```

Move card brand icon to the left:

```swift
PayabliPaymentMethodFormConfiguration(
    cardBrandIconPlacement: .leading
)
```

Render API errors at the top:

```swift
PayabliPaymentMethodFormConfiguration(
    errorMessagePlacement: .top
)
```

### QA checklist

- Confirm the partner backend returns a non-empty access token.
- Confirm sandbox uses `https://api-sandbox.payabli.com`.
- Confirm QA uses `https://api-qa.payabli.com`.
- Enable diagnostics and verify the logged URL includes the expected query
  parameters.
- Verify logged bodies redact card, ACH, token, customer, and stored method
  values.
- Test card number Luhn behavior by typing an invalid 12+ digit number and
  confirming `Invalid Card Number` renders without sheet flicker.
- Test card brand icon placement on both left and right.
- Test expiration month/year wheel selection.
- Test card input caps: name 60, PAN 19 digits, CVV 4 digits, ZIP 12 chars.
- Test ACH input caps: routing 9 digits, account 17 digits, holder 60 chars.
- Test server failure UX with the local failure mock.
- Test success navigation or success state with the local success mock.
- Test inline and sheet presentations if the integrator will use both.

### Sample app notes

Sample app files:

- `Example/PayabliDemo/PaymentMethodQAView.swift`
- `Example/PayabliDemo/PaymentMethodQAConfiguration.swift`
- `Example/PayabliDemo/PaymentMethodQAMockTransport.swift`
- `Example/PayabliDemo/PaymentMethodAddedView.swift`
- `Example/PayabliDemo/Secrets.swift.sample`
- `Example/PayabliDemo/LocalTokenServer/README.md`

The sample app reads QA/development toggles from `Secrets.swift`, which is
gitignored. Keep private Payabli credentials out of committed source.

### Where to look next

- Component overview: `Documentation/PaymentMethodOverview.md`
- Step-by-step integration: `Documentation/PaymentMethodIntegrationGuide.md`
- Sample app setup: `Example/PayabliDemo/README.md`
- Maintainer notes: `Sources/PayabliSDKPaymentMethod/README.md`
