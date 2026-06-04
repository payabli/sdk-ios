# PayabliSDKPaymentCapture LLM Reference

This file is the compact context pack for answering product, developer, and
solution-engineering questions about the Payabli iOS Payment Capture component.
It describes the current implementation in this folder. Prefer this file when
an LLM needs a fast, accurate answer; use `README.md` and
`Documentation/PaymentCaptureOverview.md` for examples and coverage commands.

## Product Persona

### What problem does this component solve?

`PayabliSDKPaymentCapture` lets an iOS app submit v2 MoneyIn transaction
requests for:

- Authorize-and-capture in one step.
- Card authorization.
- Capture of a previously authorized transaction.

### Why does it exist?

The component gives Payabli integrators a reusable native iOS API for building
transaction requests without duplicating payment method validation, sensitive
field redaction, bearer-token request construction, transaction response
decoding, and decline/error handling.

### Core product values

- Backend-owned credentials: the mobile app supplies a short-lived Bearer token
  through `accessTokenProvider`; it must not ship a private Payabli
  `clientSecret`.
- PaymentMethod parity where useful: card, ACH, customer, validation, and
  diagnostics behavior reuse the same data models and token approach as
  `PayabliSDKPaymentMethod`.
- Transaction coverage: card, ACH, stored-method, cloud-device, check, and
  cash methods are supported for one-step capture; card methods are supported
  for authorization.
- PaymentMethod UI parity: the component exposes a flat SwiftUI form and a
  bottom-sheet modifier that use PaymentMethod-compatible field labels,
  placeholders, sections, spacing, hidden labels, input sizing, and styling.
- QA visibility: development diagnostics log the final URL, query string,
  headers, request body, and response body after sensitive values are redacted.

### Current capabilities

- `capture(_:)` posts to `POST /api/v2/MoneyIn/getpaid`.
- `authorize(_:)` posts to `POST /api/v2/MoneyIn/authorize`.
- `captureAuthorizedTransaction(_:)` posts to
  `POST /api/v2/MoneyIn/capture/{transId}`.
- Card transaction payloads from `PayabliCardPaymentMethodData`.
- ACH transaction payloads from `PayabliACHPaymentMethodData`.
- Stored method transactions with configurable stored method type and usage
  type.
- Cloud-device, check, and cash one-step capture payloads.
- `idempotencyKey`, `achValidation`, and `forceCustomerCreation` request
  support where the endpoint accepts them. These are request configuration
  values, not shopper-facing controls.
- `customerData`, `accountId`, `orderId`, `orderDescription`, `ipAddress`,
  `source`, `subdomain`, and `subscriptionId` body support.
- `operation` on `PayabliPaymentCapture` selects `.capture` or `.authorize`
  for configured form submission.
- `PayabliPaymentCaptureRequestConfiguration` supplies configured payment
  details and query/body defaults for the SwiftUI form.
- `PayabliPaymentCaptureView` renders the flat/inline form.
- `.payabliPaymentCaptureSheet(...)` renders the same form inside a sheet.
- Published SwiftUI-friendly state: `isSubmitting` and `lastResult`.
- Redacted diagnostics for development and QA.
- Focused XCTest coverage for request serialization, authorization headers,
  configured form submission, query parameters, declines, diagnostics
  redaction, and facade state.

### Current boundaries

- The SwiftUI form supports card and ACH entry because it mirrors
  PaymentMethod. Direct API calls still support stored-method, cloud-device,
  check, and cash payloads.
- This component uses the Bearer token approach only. It intentionally does not
  use `requestToken`.
- This component does not create a partner backend. The integrator must provide
  a backend endpoint that exchanges Payabli server-side credentials for an
  access token.
- This component must not receive or store a long-lived Payabli private token
  in production mobile app code.
- `authorize(_:)` is card-only. ACH, cloud, check, and cash methods use
  `capture(_:)`.

## Developer Persona

### Package and module

- Swift package product: `PayabliSDKPaymentCapture`
- Main module: `PayabliSDKPaymentCapture`
- Depends on: `PayabliSDKCore`, `PayabliSDKPaymentMethod`
- Not part of the `PayabliSDK` umbrella on this branch; host apps link it
  explicitly.

Import:

```swift
import PayabliSDKPaymentCapture
import PayabliSDKPaymentMethod
```

### Public component facade

Primary type:

```swift
@MainActor
public final class PayabliPaymentCapture: NSObject, ObservableObject, PayabliComponent
```

Component metadata:

| Property | Value |
|---|---|
| `componentId` | `paymentCapture` |
| `sessionTier` | `.tier1Transactional` |
| `requiredPermissions` | `["moneyin:getpaid", "moneyin:authorize", "moneyin:capture"]` |

Production initializer:

```swift
PayabliPaymentCapture(
    entryPoint: String,
    environment: PayabliEnvironment,
    accessTokenProvider: @escaping PayabliPaymentCaptureAccessTokenProvider,
    transport: (any PayabliTransport)? = nil,
    diagnostics: PayabliPaymentCaptureDiagnostics = .disabled,
    operation: PayabliPaymentCaptureOperation = .capture,
    requestConfiguration: PayabliPaymentCaptureRequestConfiguration? = nil
)
```

Conveniences:

- `init(config:accessTokenProvider:transport:diagnostics:operation:requestConfiguration:)`
- `init(accessToken:entryPoint:environment:transport:diagnostics:operation:requestConfiguration:)`
  for tests, demos, or ephemeral tokens only.
- `configure(config:)` to repoint the component at another entry point and
  environment.
- `configure(config:theme:)` for legacy component-call compatibility.
- `configure(operation:requestConfiguration:)` and
  `configure(requestConfiguration:)` to update configured form submission
  behavior.

Published state:

- `isSubmitting`
- `lastResult`

### SwiftUI form integration

Flat form:

```swift
PayabliPaymentCaptureView(
    component: capture,
    configuration: PayabliPaymentCaptureFormConfiguration(
        allowedMethods: [.card, .ach],
        labels: PayabliPaymentCaptureLabels(submitButton: "Submit Payment")
    ),
    onPaymentCaptured: { result in ... }
)
```

Sheet form:

```swift
.payabliPaymentCaptureSheet(
    isPresented: $isPresented,
    component: capture,
    configuration: PayabliPaymentCaptureFormConfiguration(allowedMethods: [.card]),
    onPaymentCaptured: { result in ... }
)
```

Form configuration types intentionally mirror PaymentMethod:

- `PayabliPaymentCaptureFormConfiguration`
- `PayabliPaymentCaptureLabels`
- `PayabliPaymentCaptureField`
- `PayabliPaymentCaptureFieldSection`
- `PayabliPaymentCaptureHiddenValues`
- `PayabliPaymentCaptureFormatting`
- `PayabliPaymentCaptureInputSizing`
- `PayabliPaymentCaptureStyle`
- `PayabliPaymentCaptureSheetConfiguration`

The form collects payment/customer inputs plus a read-only "Payment Information"
section for Amount and Fee. Amount and Fee are rendered from
`requestConfiguration.paymentDetails`; by default each row displays the label
on the left (`Amount:` / `Fee:`) and the amount on the right (`$ 1.00` /
`$ 0.10`). The section heading text is configurable through
`PayabliPaymentCaptureFieldSection.title`; heading font/color can be configured
per section with `PayabliPaymentCaptureFieldSection.titleStyle`, falling back
to the global `PayabliPaymentCaptureStyle.sectionTitle` when omitted.
Integrators can override amount/fee label text, amount/fee value text,
label/value font and color, and row spacing through
`PayabliPaymentCapturePaymentSummaryConfiguration`. Operation,
currency, order/source metadata, idempotency, `achValidation`, and
`forceCustomerCreation` remain component/request configuration and are not shown
as UI controls.

### Authentication integration

Every submit calls the host-provided `accessTokenProvider` immediately before
building the request. The provider must return the Bearer access token string.

The SDK then sends:

```text
Authorization: Bearer <access token>
```

The SDK does not send:

```text
requestToken: ...
```

The server-side Payabli token exchange is not performed by the SDK. A partner
backend can call the environment-specific server-side token endpoint and return
only the scoped `access_token` to the mobile app.

### Endpoint requests

Request construction lives in `PaymentCaptureClient.swift`.

Headers:

- `Authorization: Bearer <token>`
- `Content-Type: application/json`
- `idempotencyKey` when `PayabliPaymentCaptureRequest.idempotencyKey` is set.

One-step capture:

```text
POST /api/v2/MoneyIn/getpaid
```

Authorization:

```text
POST /api/v2/MoneyIn/authorize
```

Capture authorized transaction:

```text
POST /api/v2/MoneyIn/capture/{transId}
```

### Public request models

- `PayabliPaymentCaptureRequest`
- `PayabliPaymentCaptureRequestConfiguration`
- `PayabliPaymentCaptureAuthorizedRequest`
- `PayabliPaymentCapturePaymentDetails`
- `PayabliPaymentCapturePaymentMethod`
- `PayabliPaymentCaptureCardMethod`
- `PayabliPaymentCaptureACHMethod`
- `PayabliPaymentCaptureStoredMethod`
- `PayabliPaymentCaptureCloudMethod`
- `PayabliPaymentCaptureCheckMethod`

### Public response models

- `PayabliPaymentCaptureResult`
- `PayabliPaymentCaptureAPIResponse`
- `PayabliPaymentCaptureTransaction`
- `PayabliPaymentCaptureResponseData`
- `PayabliPaymentCaptureFailure`
- `PayabliPaymentCaptureError`

### Error behavior

- Empty entrypoint, invalid amount, invalid card/ACH values, missing transaction
  ID, or unsupported authorization methods throw
  `PayabliPaymentCaptureError.invalidInput`.
- Empty bearer token throws `PayabliPaymentCaptureError.missingAccessToken`.
- Decodable non-approved Payabli response envelopes throw
  `PayabliPaymentCaptureError.transactionFailed`.
- Non-decodable HTTP errors fall back to Core's canonical
  `mapPayabliHTTPError(response:)`.

### Diagnostics

`PayabliPaymentCaptureDiagnostics.enabled { entry in ... }` emits request,
response, and failure entries. It redacts:

- `Authorization`, `requestToken`, and token-like fields.
- Card number, CVV, and card postal code fields.
- ACH account and routing fields.
- Customer personal fields such as name, address, email, and phone.

## Important Implementation Files

- `PayabliPaymentCapture.swift`: public facade, state, configuration, and
  submit methods.
- `PaymentCaptureClient.swift`: endpoint paths, query/header serialization,
  bearer token handling, transport calls, and response decoding.
- `PayabliPaymentCaptureFormConfiguration.swift`: Capture-specific field/form
  configuration plus PaymentMethod-compatible style and sheet aliases.
- `PayabliPaymentCaptureView.swift`: flat SwiftUI form.
- `PayabliPaymentCaptureViewModel.swift`: transient card/ACH/customer field
  state and configured request assembly.
- `PayabliPaymentCaptureSheet.swift`: sheet modifier and sheet content.
- `PayabliPaymentCaptureTypes.swift`: public request/response DTOs, method
  encoding, validation, and local errors.
- `PayabliPaymentCaptureDiagnostics.swift`: redacted diagnostic payloads.
- `PayabliSDKPaymentCapture.swift`: module metadata and access token provider
  typealias.

## Test Commands

Focused tests:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPaymentCaptureTests
```

Focused coverage:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPaymentCaptureTests \
  -enableCodeCoverage YES \
  -resultBundlePath build/TestResults/PaymentCaptureCoverage.xcresult
xcrun xccov view --report build/TestResults/PaymentCaptureCoverage.xcresult
```
