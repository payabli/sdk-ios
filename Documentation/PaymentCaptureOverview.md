# PayabliSDKPaymentCapture Overview

`PayabliSDKPaymentCapture` is the opt-in transaction component for Payabli v2
MoneyIn auth and capture workflows. It complements
`PayabliSDKPaymentMethod`: PaymentMethod stores card or ACH credentials, while
PaymentCapture submits card, ACH, stored-method, cloud-device, check, or cash
transactions.

## Endpoint Coverage

| Flow | SDK call | Endpoint |
| --- | --- | --- |
| Authorize and capture in one step | `capture(_:)` | `POST /api/v2/MoneyIn/getpaid` |
| Authorize card transaction | `authorize(_:)` | `POST /api/v2/MoneyIn/authorize` |
| Capture previous authorization | `captureAuthorizedTransaction(_:)` | `POST /api/v2/MoneyIn/capture/{transId}` |

Payabli references:

- [Make a transaction](https://docs.payabli.com/developers/api-reference/moneyinV2/make-a-transaction)
- [Authorize a transaction](https://docs.payabli.com/developers/api-reference/moneyinV2/authorize-a-transaction)
- [Capture a transaction](https://docs.payabli.com/developers/api-reference/moneyinV2/capture-a-transaction)

## Authentication

PaymentCapture uses the same mobile token model as PaymentMethod. The host app
passes an async access-token provider, and the SDK sends the token as:

```text
Authorization: Bearer <token>
```

The component does not send the legacy `requestToken` header. Keep the private
Payabli API secret on the host application's backend and return only scoped,
short-lived access tokens to the iOS app.

## Installation

Link the opt-in product from Swift Package Manager:

```swift
.product(name: "PayabliSDKPaymentCapture", package: "sdk-ios")
```

PaymentCapture depends on `PayabliSDKCore` and `PayabliSDKPaymentMethod` so it
can reuse the same card, ACH, customer, and validation models.

## SwiftUI Form Example

`PayabliPaymentCaptureView` is the inline form surface. It intentionally mirrors
the PaymentMethod component's UI and configuration model: section names,
hidden labels, placeholder text, spacing, input sizing, and style all use
PaymentMethod-compatible `PayabliPaymentCapture*` configuration types.

Operation and request flags are not shopper-facing UI. Configure them on the
component and `PayabliPaymentCaptureRequestConfiguration`.

```swift
import PayabliSDKPaymentCapture
import PayabliSDKPaymentMethod

let capture = PayabliPaymentCapture(
    entryPoint: "your-entrypoint",
    environment: .sandbox,
    accessTokenProvider: { try await backend.fetchPaymentToken() },
    operation: .capture,
    requestConfiguration: PayabliPaymentCaptureRequestConfiguration(
        paymentDetails: PayabliPaymentCapturePaymentDetails(
            totalAmount: 100,
            serviceFee: 0,
            currency: "USD"
        ),
        orderId: "ORDER-1001",
        source: "ios-checkout",
        idempotencyKey: UUID().uuidString,
        achValidation: true,
        forceCustomerCreation: true
    )
)

PayabliPaymentCaptureView(
    component: capture,
    configuration: PayabliPaymentCaptureFormConfiguration(
        allowedMethods: [.card, .ach],
        labels: PayabliPaymentCaptureLabels(
            title: "Payment",
            submitButton: "Submit Payment"
        )
    ),
    onPaymentCaptured: { result in
        print(result.transaction?.paymentTransId ?? "")
    }
)
```

The form includes a read-only "Payment Information" section before the submit
button. Amount and Fee are rendered from `requestConfiguration.paymentDetails`
and default to stacked rows with `Amount:` / `Fee:` labels on the left and
`$ 1.00` / `$ 0.10` values on the right. Integrators can override the section
heading text with `PayabliPaymentCaptureFieldSection.title`, style that heading
per section with `titleStyle`, and override each label and value, plus
label/value font, color, and row spacing with
`PayabliPaymentCapturePaymentSummaryConfiguration`; endpoint operation,
currency, order/source metadata, idempotency, and ACH query flags remain
configuration.

## Sheet Example

```swift
Button("Open payment sheet") {
    isPaymentSheetPresented = true
}
.payabliPaymentCaptureSheet(
    isPresented: $isPaymentSheetPresented,
    component: capture,
    configuration: PayabliPaymentCaptureFormConfiguration(
        allowedMethods: [.card],
        labels: PayabliPaymentCaptureLabels(title: "Authorize Card")
    ),
    sheetConfiguration: PayabliPaymentCaptureSheetConfiguration(
        dismissButton: .back
    ),
    onPaymentCaptured: { result in
        print(result.code)
    }
)
```

## Direct API Example

```swift
let result = try await capture.authorize(PayabliPaymentCaptureRequest(
    paymentDetails: PayabliPaymentCapturePaymentDetails(totalAmount: 100),
    paymentMethod: .card(PayabliPaymentCaptureCardMethod(data: cardData)),
    customerData: PayabliPaymentMethodCustomerData(customerId: 4440)
))

print(result.transaction?.paymentTransId ?? "")
```

## Supported Payment Methods

`PayabliPaymentCapturePaymentMethod` supports:

- `.card(PayabliPaymentCaptureCardMethod)`
- `.ach(PayabliPaymentCaptureACHMethod)`
- `.stored(PayabliPaymentCaptureStoredMethod)`
- `.cloud(PayabliPaymentCaptureCloudMethod)`
- `.check(PayabliPaymentCaptureCheckMethod)`
- `.cash`

Only card methods can use `authorize(_:)`. ACH, cloud, check, and cash should
use the one-step `capture(_:)` flow.

## Diagnostics

Use `PayabliPaymentCaptureDiagnostics.enabled { ... }` to inspect redacted
request, response, and failure entries during integration. Authorization,
token, PAN, CVV, ACH account, routing, and customer PII fields are redacted
before diagnostics are emitted.

## Tests And Coverage

Run focused tests with:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPaymentCaptureTests
```

Run a focused coverage report with:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPaymentCaptureTests \
  -enableCodeCoverage YES \
  -resultBundlePath build/TestResults/PaymentCaptureCoverage.xcresult
xcrun xccov view --report build/TestResults/PaymentCaptureCoverage.xcresult
```
