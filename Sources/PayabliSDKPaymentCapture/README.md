# PayabliSDKPaymentCapture

`PayabliSDKPaymentCapture` is an opt-in component for v2 MoneyIn transaction
flows:

- `POST /api/v2/MoneyIn/getpaid` for authorize-and-capture in one step.
- `POST /api/v2/MoneyIn/authorize` for card authorization.
- `POST /api/v2/MoneyIn/capture/{transId}` for capturing an authorized
  transaction.

Official endpoint references:

- [Make a transaction](https://docs.payabli.com/developers/api-reference/moneyinV2/make-a-transaction)
- [Authorize a transaction](https://docs.payabli.com/developers/api-reference/moneyinV2/authorize-a-transaction)
- [Capture a transaction](https://docs.payabli.com/developers/api-reference/moneyinV2/capture-a-transaction)

The component follows the same mobile security model as
`PayabliSDKPaymentMethod`: host applications provide a short-lived scoped
bearer token through an async provider, and the SDK sends
`Authorization: Bearer <token>`. It does not send the legacy `requestToken`
header.

Capture also exposes PaymentMethod-style SwiftUI form surfaces:

- `PayabliPaymentCaptureView` for flat/inline rendering.
- `.payabliPaymentCaptureSheet(...)` for bottom-sheet presentation.
- PaymentMethod-compatible field labels, placeholders, sections, spacing,
  hidden field labels, input sizing, and styling via the
  `PayabliPaymentCapture*` configuration types.

Shopper-facing forms collect payment/customer fields plus read-only Amount and
Fee display text. Transaction operation (`.capture` or `.authorize`) and request
flags such as `achValidation`, `forceCustomerCreation`, and `idempotencyKey`
are configured on the component/request configuration, not exposed as UI
controls.

References:

- [`Documentation/PaymentCaptureOverview.md`](../../Documentation/PaymentCaptureOverview.md)
  for integration examples and coverage commands.
- [`LLM.md`](LLM.md) for compact product and developer context.

## Maintainer Notes

- `PayabliPaymentCapture.swift` owns the public component facade and dependency
  injection points.
- `PaymentCaptureClient.swift` owns v2 MoneyIn request construction, bearer
  authorization, query/header serialization, response decoding, and diagnostics.
- `PayabliPaymentCaptureTypes.swift` owns public DTOs, response models,
  validation helpers, and local errors.
- `PayabliPaymentCaptureFormConfiguration.swift` exposes the Capture-specific
  field model, including amount and fee fields, while reusing PaymentMethod
  style and sheet primitives.
- `PayabliPaymentCaptureView.swift`, `PayabliPaymentCaptureViewModel.swift`,
  and `PayabliPaymentCaptureSheet.swift` own the SwiftUI flat and sheet form
  surfaces.
- `PayabliPaymentCaptureDiagnostics.swift` owns redacted request/response
  diagnostics.

Run focused tests with:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPaymentCaptureTests
```

## Example

```swift
let capture = PayabliPaymentCapture(
    entryPoint: "f743aed24a",
    environment: .sandbox,
    accessTokenProvider: { try await backend.fetchPaymentCaptureAccessToken() },
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
        labels: PayabliPaymentCaptureLabels(submitButton: "Submit Payment")
    ),
    onPaymentCaptured: { result in
        print(result.transaction?.paymentTransId ?? "")
    }
)
```

The configured `paymentDetails.totalAmount` and `paymentDetails.serviceFee`
render the form's read-only "Payment Information" section. By default the rows
display `Amount:` on the left with `$ 1.00` on the right, then `Fee:` on the
left with `$ 0.10` on the right. The section heading text is configurable with
`PayabliPaymentCaptureFieldSection.title`, and per-section heading font/color
are configurable with `titleStyle`. Integrators can override each label and
value, plus label/value font, color, and row spacing through
`PayabliPaymentCapturePaymentSummaryConfiguration`.
Currency, order/source metadata, idempotency, and ACH query flags remain
component/request configuration and are not exposed as UI controls.

```swift
PayabliPaymentCaptureFormConfiguration(
    cardSections: [
        PayabliPaymentCaptureFieldSection(
            title: "Payment Information",
            titleStyle: PayabliPaymentCaptureTextStyle(
                font: .headline,
                color: .primary
            ),
            fields: [.amount, .serviceFee],
            inputVerticalSpacing: 8
        )
    ],
    paymentSummary: PayabliPaymentCapturePaymentSummaryConfiguration(
        amountLabelText: "Amount:",
        amountValueText: "$ 1.00",
        feeLabelText: "Fee:",
        feeValueText: "$ 0.10",
        labelStyle: PayabliPaymentCapturePaymentSummaryTextStyle(
            font: .subheadline,
            color: .secondary
        ),
        valueStyle: PayabliPaymentCapturePaymentSummaryTextStyle(
            font: .subheadline.weight(.semibold),
            color: .primary
        ),
        rowSpacing: 8
    )
)
```

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
    onPaymentCaptured: { result in
        print(result.code)
    }
)
```
