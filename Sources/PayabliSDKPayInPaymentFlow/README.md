# PayabliSDKPayInPaymentFlow

`PayabliSDKPayInPaymentFlow` is the unified PayIn component for iOS card and ACH flows.

Use it to:

- store card or ACH payment methods with `/api/TokenStorage/add`
- capture or authorize MoneyIn v2 transactions
- capture a prior authorization by transaction ID
- render the same SwiftUI form inline or in the SDK bottom sheet
- configure labels, placeholders, sections, per-section spacing, per-field spacing, fonts, colors, card-brand icons, diagnostics, and accessibility metadata

## Component

```swift
import PayabliSDKPayInPaymentFlow

@StateObject private var paymentFlow = PayabliPayInPaymentFlow(
    entryPoint: "merchant-entry",
    environment: .sandbox,
    accessTokenProvider: {
        try await Backend.shared.fetchMobilePayInToken()
    },
    operation: .storePaymentMethod
)
```

Set `operation` to `.storePaymentMethod`, `.capture`, or `.authorize`. Capture and authorize require `PayabliPayInPaymentFlowRequestConfiguration` during initialization or direct API calls.

Authorize is intentionally narrower than capture: it accepts card data only today. ACH, stored payment methods, cash, check, and cloud-device payments are rejected before transport for `.authorize`. The authorize capability is modeled separately so Apple Pay or other future authorizable methods can be added without changing the capture/store flows.

The component uses the same mobile access-token approach as the stored-method flow. Do not pass a `requestToken` header directly.

Use `captureAuthorizedTransaction(_:)` for `/api/v2/MoneyIn/capture/{transId}`. That operation is a direct API; the hosted form supports stored-method, capture, and authorize submissions.

## Security Model

When an app uses the SDK-hosted SwiftUI view or sheet, clear PAN is kept inside SDK-owned state and is not written into the hosted `UITextField.text`, accessibility value, diagnostics, or public callbacks. The public component initializers always use the SDK transport; custom transport injection is reserved for internal tests.

Direct card-data APIs such as `addCard(_:)`, `capture(_:)`, and `authorize(_:)` are PCI-sensitive by design because the host app creates and passes `PayabliPayInPaymentFlowCardData`. Use the hosted form when the integration goal is to avoid host-app access to clear PAN.

## SwiftUI

```swift
PayabliPayInPaymentFlowView(
    component: paymentFlow,
    configuration: configuration,
    onCompleted: { result in
        // Keep the identifiers, do not log them: a stored-method id is a token.
        if let storedMethod = result.storedPaymentMethod {
            storedMethodId = storedMethod.storedMethodId
        } else {
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
.payabliPayInPaymentFlowStyle(style)
```

Use `.payabliPayInPaymentFlowSheet(...)` for the sheet presentation. It renders the same form and accepts the same configuration and style.

## Form Configuration

`PayabliPayInPaymentFlowFormConfiguration` controls displayed fields and behavior:

- `allowedMethods` and `defaultMethod`
- `cardFieldOrder`, `achFieldOrder`
- `cardSections`, `achSections`
- `hiddenValues`
- `options`
- `labels`
- `labelLayout`
- `showsFieldLabels`
- `hiddenFieldLabels`
- `formatting`
- `inputSizing`
- `cardBrandIconPlacement`
- `requiredFields`
- `paymentSummary`

Labels and section names are configurable. Input placeholders can be configured per field with `PayabliPayInPaymentFlowLabels(fieldPlaceholders:)`. Use `labelLayout: .placeholder` or `showsFieldLabels: false` to hide visible labels while keeping accessible labels.

The default field labels use `Postal Code` and `Billing Postal Code`.

## Sections And Spacing

Group fields with `PayabliPayInPaymentFlowFieldSection`:

```swift
PayabliPayInPaymentFlowFieldSection(
    title: "Card Information",
    fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip],
    inputVerticalSpacing: 4,
    inputHorizontalSpacing: 8,
    fieldVerticalSpacings: [
        .cardNumber: 2,
        .cardCvv: 2
    ]
)
```

Capture and authorize forms include a `Payment Information` section for non-editable amount and fee rows. Store-payment-method mode filters those payment summary rows from the rendered form.

## Styling

`PayabliPayInPaymentFlowStyle` controls:

- title, subtitle, label, section title, error, and submit button text styles
- SwiftUI input font and UIKit text-field font with `input.uiFont`
- input text, placeholder, background, focus, border, and picker icon colors
- layout spacing

Custom fonts must be registered by the host app. Add the font files to the app target, list them in `UIAppFonts` in `Info.plist`, then use both `Font.custom(_:size:)` for SwiftUI text and `UIFont(name:size:)` for UIKit-backed text fields.

## Accessibility

The form is built for standard iOS accessibility checks:

- minimum 44 pt touch targets
- accessible labels even when visible labels are hidden
- secure accessibility values for card number, CVV, ACH account, and ACH routing fields
- card-number validation announcements
- stable accessibility identifiers via `PayabliPayInPaymentFlowAccessibility.fieldIdentifier(_:)`
- Dynamic Type support, including unpairing horizontal fields at accessibility sizes

Run focused tests with:

```bash
xcodebuild test -scheme PayabliSDK-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' \
  -only-testing:PayabliSDKPayInPaymentFlowTests
```
