# PayabliSDKPayInPaymentFlow Overview

`PayabliSDKPayInPaymentFlow` is the unified iOS PayIn component for stored payment methods, capture, and authorization.

Add the product:

```swift
.product(name: "PayabliSDKPayInPaymentFlow", package: "sdk-ios")
```

Import:

```swift
import PayabliSDKPayInPaymentFlow
```

Supported operations:

- `.storePaymentMethod`
- `.capture`
- `.authorize`

The component supports direct async API calls and a turn-key SwiftUI form that can be embedded inline or presented as a sheet. Capturing a prior authorization is available through the direct `captureAuthorizedTransaction(_:)` API.

Use the same mobile access-token provider model for all operations. Capture and authorize do not use a manually supplied `requestToken` header.

Authorize currently supports card data only. ACH, stored methods, cash, check, and cloud-device payment methods are not valid authorize inputs. The SDK keeps authorization eligibility separate from capture methods so future Apple Pay support can be added as its own authorizable method.

## Security Model

The SDK-hosted SwiftUI view and sheet are the recommended integration paths when the host app should not access clear PAN. In hosted entry, the full card number is not written into host-visible `UITextField.text`, accessibility values, diagnostics, callbacks, or result models.

Direct async APIs remain PCI-sensitive because the host app creates and passes the raw card data. Use hosted entry for PAN isolation; use direct APIs only when the integrator is prepared to handle clear card data.

## SwiftUI

```swift
PayabliPayInPaymentFlowView(
    component: paymentFlow,
    configuration: configuration,
    onCompleted: { result in
        switch result.kind {
        case .storedPaymentMethod:
            print(result.storedPaymentMethod?.storedMethodId ?? "")
        case .transaction:
            print(result.transaction?.paymentTransId ?? "")
        }
    }
)
```

Sheet:

```swift
.payabliPayInPaymentFlowSheet(
    isPresented: $isPresented,
    component: paymentFlow,
    configuration: configuration,
    sheetConfiguration: PayabliPayInPaymentFlowSheetConfiguration(title: "Submit Payment"),
    style: style,
    onCompleted: { result in }
)
```

## Capabilities

- configurable external labels and placeholder text
- configurable section names and section title styles
- vertical and horizontal spacing per section
- vertical spacing after individual fields
- custom SwiftUI fonts and UIKit input fonts
- input text, placeholder, label, section title, submit, error, amount, and fee colors
- read-only amount and fee payment summary rows for capture/authorize
- direct prior-authorization capture by transaction ID
- card brand icon detection and placement
- card and ACH validation
- redacted diagnostics and PAN-pattern scrubbing for failure messages
- accessibility labels, hints, identifiers, Dynamic Type behavior, and secure values

See `Sources/PayabliSDKPayInPaymentFlow/LLM.md` for the code-generation guide and detailed API map.
