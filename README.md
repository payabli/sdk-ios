# PayabliSDK for iOS

Native iOS SDK to accept payments with Payabli — drop-in SwiftUI forms, Apple Pay, and Tap to Pay on iPhone.

Set up once, then drop a form in anywhere:

```swift
import PayabliSDKPayIn

CardFormView(customerId: 4440) { token, error in
    // `token` is a reusable methodReferenceId you store on your backend.
}
```

Style it with `PayabliTheme`, localize it with `CardFormStrings`, present it as a sheet, or wrap it in a `UIViewController` — same callback either way.

> Part of Payabli **Embedded Components V2**. See [RFC-0001](./RFC-0001-payabli-sdk-ios.md) for the full v1.0 design.

---

## What's inside


| Capability           | What it does                                    | Min iOS           |
| -------------------- | ----------------------------------------------- | ----------------- |
| Tokenization         | Save a card or ACH method for later.            | 15.0              |
| Process payment      | One-time charge with a form or a stored method. | 15.0              |
| Apple Pay            | Tokenize or charge through Apple's sheet.       | 15.0              |
| Tap to Pay on iPhone | Card-present NFC, no external reader.           | 16.7 (iPhone XS+) |


Swift 5.9+, Xcode 15+. Available as Swift Package Manager and CocoaPods.

---

## Install

### Swift Package Manager

```swift
.package(url: "https://github.com/payabli/payabli-sdk-ios.git", from: "1.0.0")
```

Pick the product you need:


| Product           | Includes                                        |
| ----------------- | ----------------------------------------------- |
| `PayabliSDK`      | Everything (Core + PayIn) — pick this if unsure |
| `PayabliSDKPayIn` | Tokenization, getpaid, Apple Pay, Tap to Pay    |
| `PayabliSDKCore`  | Just the primitives (config, auth, networking)  |


### CocoaPods

```ruby
pod 'PayabliSDK', '~> 1.0'        # everything
pod 'PayabliSDK/PayIn', '~> 1.0'  # core + payin
pod 'PayabliSDK/Core',  '~> 1.0'  # core only
```

---

## One-time setup

The SDK never sees your `clientSecret`. Your backend exchanges it for a short-lived `access_token` and the app uses that.

```text
Mobile app  ──▶  Your backend  ──▶  POST /api/v2/token/serverside  (Payabli)
            ◀──  access_token  ◀──
```

Configure once at app start:

```swift
import PayabliSDKPayIn

let token = try await yourBackend.fetchPayabliAccessToken()

let config = PayabliConfig(
    accessToken: token,
    tokenProvider: { try await yourBackend.fetchPayabliAccessToken() },
    entryPoint: "f743aed24a",
    environment: .sandbox
)

PayabliPayIn.shared.configure(config: config, theme: .default)
```

`tokenProvider` is your refresh hook: when a request gets `401 Unauthorized`, the SDK calls it and retries automatically. Concurrent 401s are deduplicated under the hood.

> Tap to Pay is the one exception — it takes its own `accessToken` directly and does **not** require `PayabliPayIn.configure(...)`. See [Tap to Pay on iPhone](#tap-to-pay-on-iphone) below.

---

## Save a payment method (tokenization)

A drop-in form that validates input, calls `POST /api/TokenStorage/add`, and hands you back a reusable `methodReferenceId`.

Three equivalent entry points — pick the one that fits your stack:

**1. SwiftUI — embedded view**

```swift
CardFormView(customerId: 4440) { token, error in
    // token: String? — the reusable methodReferenceId
}
```

**2. SwiftUI — sheet** *(turn-key: header, Cancel button, swipe-to-dismiss)*

```swift
@State private var show = false

Button("Save card") { show = true }
    .payabliCardSheet(isPresented: $show, customerId: 4440) { token, error in
        // ...
    }
```

**3. UIKit — `async` or callback**

```swift
// async — the SDK presents and dismisses for you
let token = try await PayabliPayIn.shared.tokenize(
    type: .card,
    customerId: 4440,
    from: self
)

// callback — you present the returned controller
let vc = PayabliPayIn.shared.createTokenizationViewController(
    type: .card,
    customerId: 4440
) { token, error in /* ... */ }
present(vc, animated: true)
```

> **Need ACH instead?** Same shape: `ACHFormView`, `.payabliAchSheet(...)`, `type: .ach`.

User cancellation (Cancel button or swipe-to-dismiss) surfaces as `PayabliGenericError(code: .userCancelled)`.

---

## Charge a customer (getpaid)

Same shape as tokenization, but you pass a `PayabliPaymentRequest` and get back a `PayabliTransactionResult`.

```swift
let request = PayabliPaymentRequest(
    totalAmount: 49.99,
    currency: "USD",
    orderId: "order-1234",
    saveIfSuccess: true   // also tokenize on success
)
```

### With a form (UI)

```swift
// SwiftUI — embedded
CardFormView(paymentRequest: request, customerId: 4440) { result, error in
    // result?.paymentTransId, result?.methodReferenceId (when saveIfSuccess)
}

// SwiftUI — sheet
.payabliCardSheet(isPresented: $show, paymentRequest: request, customerId: 4440) { result, error in
    // ...
}

// UIKit — async
let result = try await PayabliPayIn.shared.processPayment(
    type: .card,
    paymentRequest: request,
    customerId: 4440,
    from: self
)
```

### Headless (stored method, no UI)

```swift
let request = PayabliPaymentRequest(
    totalAmount: 19.99,
    storedMethodId: savedMethodReferenceId
)

let result = try await PayabliPayIn.shared.chargeStoredMethod(
    methodType: .card,
    paymentRequest: request,
    customerId: 4440
)
```

Stored-method charges default to `initiator: .merchant` for MIT compliance — override `paymentRequest.initiator` when needed.

---

## Apple Pay

The same `PayabliApplePayConfig` powers both modes:

```swift
let applePayConfig = PayabliApplePayConfig(
    merchantIdentifier: "merchant.com.yourcompany.app",
    merchantName: "Your Merchant Name"
)
```

**Set Up** — tokenize for later use:

```swift
let token = try await PayabliPayIn.shared.setupApplePay(
    applePayConfig: applePayConfig,
    amount: 0.00,            // zero-auth tokenization
    customerId: 4440
)
```

**Pay** — authorize and capture now:

```swift
let result = try await PayabliPayIn.shared.chargeApplePay(
    applePayConfig: applePayConfig,
    paymentRequest: PayabliPaymentRequest(totalAmount: 49.99, orderId: "order-5678"),
    customerId: 4440
)
```

Requires the **Apple Pay** capability on your App ID and the merchant identifier registered with Apple. Callback variants (`...completion:`) exist for Obj-C and cross-platform bridges.

---

## Tap to Pay on iPhone

Card-present NFC acceptance, no external reader. Lives in its own `PayabliTTP` class because it manages a per-device attestation cache and a multi-step session lifecycle.

### Before you start

1. **Apple entitlement.** Request `com.apple.developer.proximity-reader.payment.acceptance` from Apple — it's allowlisted, not automatic. ([Apple docs](https://developer.apple.com/tap-to-pay-on-iphone/))
2. **Bundle ID enrolled** with both Apple's Tap to Pay program and Payabli's partner onboarding.
3. **Device eligibility.** iPhone XS+, iOS 16.7+, supported region, unlocked. The SDK enforces this on `initialize()`.
4. **Tap to Pay-enabled entry point** provisioned by Payabli.

### Lifecycle

```
.idle ─▶ .attestingDevice ─▶ .fetchingConfig ─▶ .initializingReader ─▶ .ready
                              │
                              └─▶ .pendingActivation ─▶ (partner OTP) ─▶ .idle
```

First launch performs **cold attestation** (Apple's App Attest + Payabli `/register` & `/attest`). Later launches reuse the cached attestation and only refresh `/config`.

### Use it

```swift
import PayabliSDKPayIn

@MainActor
final class CheckoutViewModel: ObservableObject {
    let ttp: PayabliTTP

    init(accessToken: String, refresh: @escaping () async throws -> String) {
        self.ttp = PayabliTTP(
            accessToken: accessToken,
            tokenProvider: refresh,
            entryPoint: "f743aed24a",
            appId: "TEAM123456.com.yourcompany.app",   // TEAMID.bundle-id
            environment: .sandbox
        )
    }
}

// 1. Once per session.
try await viewModel.ttp.initialize()

// 2. Charge.
let result = try await viewModel.ttp.charge(
    amount: 9.99,
    type: .sale,
    customer: PayabliTTPCustomerData(firstName: "Jane", lastName: "Doe"),
    order: PayabliTTPOrderData(orderId: "order-9001")
)

print("paymentTransId:", result.paymentTransId)
```

`PayabliTTP` is an `ObservableObject` — bind to `sessionState` and `isReady` directly from SwiftUI.

### Reacting to events (optional)

```swift
for await event in viewModel.ttp.events() {
    switch event {
    case .readerReady:              print("Ready to tap")
    case .nfcStarted:               print("Hold card near iPhone…")
    case .updateCompleted(let id):  print("Charge complete: \(id)")
    case .devicePendingActivation:  print("Ask admin for activation code")
    default: break
    }
}
```

### Pending device activation

If the device hasn't been activated yet, `initialize()` throws `.devicePendingActivation`:

```swift
do {
    try await ttp.initialize()
} catch PayabliTTPError.devicePendingActivation {
    let code = await promptForActivationCode()        // your UI
    try await ttp.activateDevice(activationCode: code)
    try await ttp.initialize()                        // re-run after activation
}
```

The OTP is **partner-issued** — your admin dashboard calls Payabli's `/activate/challenge` endpoint server-side and delivers the code through your own channel; the SDK only consumes it.

> See `[Sources/PayabliSDKPayIn/TapToPay/README.md](./Sources/PayabliSDKPayIn/TapToPay/README.md)` for the full state machine, event catalog, and adapter contract.

---

## Customizing the forms

`CardFormView`, `ACHFormView`, and their sheet/UIKit equivalents accept the same two optional parameters in addition to `theme:`:


| Parameter       | What it controls                                                                                                                                |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `strings`       | Every visible string — labels, placeholders, errors, sheet title, submit button. Default English copy is provided; override only what you need. |
| `allowedBrands` | (Card only) Restricts accepted networks. Disallowed brands are hidden in the brand row and surface an inline error. Defaults to `.all`.         |


```swift
let cardStrings = CardFormStrings(
    sheetTitle: "Datos de tarjeta",
    holderNameLabel: "Nombre del titular",
    cardNumberLabel: "Número de tarjeta",
    expirationLabel: "MM / AA",
    cvcLabel: "CVV",
    zipLabel: "Código postal",
    saveButtonTitle: "Guardar tarjeta",
    cardNumberError: "Número de tarjeta inválido",
    disallowedBrandError: "Marca de tarjeta no aceptada"
)

CardFormView(
    customerId: 4440,
    theme: .default,
    strings: cardStrings,
    allowedBrands: [.visa, .mastercard]   // Amex / Discover hidden + rejected
) { token, error in /* ... */ }
```

`PayabliCardBrand` is an `OptionSet`: `.visa`, `.mastercard`, `.amex`, `.discover`, `.all`. Brand restriction takes precedence over Luhn — a well-formed but unsupported PAN surfaces "brand not accepted" rather than "invalid number". Partial PANs (no detected brand yet) are never blocked.

`ACHFormStrings` follows the same pattern: labels, placeholders, picker option titles (Checking/Savings/Personal/Business), validation errors, save-button title.

---

## Handling errors

Payment APIs throw `PayabliPaymentError` with four typed cases:

```swift
do {
    let result = try await PayabliPayIn.shared.processPayment(...)
} catch let PayabliPaymentError.decline(err) {
    // err.rawCode ("D0001"), err.reason, err.explanation, err.action
} catch let PayabliPaymentError.validation(err) {
    // err.errors: [String: [PayabliFieldError]] — field-level messages
} catch let PayabliPaymentError.server(err) {
    // 5xx — retry with backoff
} catch let PayabliPaymentError.generic(err) {
    // transport, configuration, .userCancelled, etc.
}
```

`PayabliGenericError(code: .userCancelled)` is the cancellation signal from any UI flow.

---

## Roadmap

`PayabliSDKPayIn` ships in v1.0. **Payout**, **Reporting**, and **Onboarding** components are on the roadmap — see [RFC-0001](./RFC-0001-payabli-sdk-ios.md) for the full plan.

---

## Demo app

```bash
cd Example/PayabliDemo
cp Config.xcconfig.sample Config.xcconfig    # fill in sandbox credentials
open PayabliDemo.xcodeproj
```

## License

Commercial. See [LICENSE](./LICENSE).