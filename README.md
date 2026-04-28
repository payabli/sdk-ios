# PayabliSDK for iOS

Native iOS SDK for Payabli payment acceptance. Drop-in SwiftUI forms for tokenization, card-not-present processing, and card-present Tap to Pay on iPhone.

Part of the Payabli **Embedded Components V2** platform. See [RFC-0001](./RFC-0001-payabli-sdk-ios.md) for the full v1.0 design.

---

## Requirements

| Feature | Minimum iOS |
| --- | --- |
| Tokenization (Card / ACH) | iOS 15.0 |
| Apple Pay | iOS 15.0 |
| Tap to Pay on iPhone | iOS 16.7, iPhone XS or later |

Swift 5.9+, Xcode 15+.

---

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/payabli/payabli-sdk-ios.git", from: "1.0.0")
]
```

Add the products you need as target dependencies:

| Product | Contains |
| --- | --- |
| `PayabliSDK` | Umbrella: Core + PayIn |
| `PayabliSDKCore` | Shared primitives (config, auth, networking) |
| `PayabliSDKPayIn` | Tokenization, getpaid, Apple Pay, Tap to Pay |

### CocoaPods

```ruby
pod 'PayabliSDK', '~> 1.0'              # umbrella (Core + PayIn)
pod 'PayabliSDK/Core', '~> 1.0'          # core only
pod 'PayabliSDK/PayIn', '~> 1.0'         # core + payin
```

---

## Authentication

> Your `clientSecret` must **never** ship in the mobile binary.

Your backend performs the token exchange server-side against `POST /api/v2/token/serverside` and returns a short-lived `access_token` to the app. The SDK receives the pre-minted token plus an optional refresh callback that re-hits your backend when the token expires.

### Your backend's token endpoint

```text
POST /payabli/token  (your URL, e.g. https://your-api.example.com/payabli/token)
→ Your server calls POST https://api-sandbox.payabli.com/api/v2/token/serverside
   with your clientId + clientSecret (held in server-side config / secrets manager).
→ Returns {"access_token": "..."} to the mobile app.
```

### Configure the SDK

```swift
import PayabliSDKPayIn

let accessToken = try await yourBackend.fetchPayabliAccessToken()

let config = PayabliConfig(
    accessToken: accessToken,
    tokenProvider: { try await yourBackend.fetchPayabliAccessToken() },
    entryPoint: "f743aed24a",
    environment: .sandbox
)

PayabliPayIn.shared.configure(config: config, theme: .default)
```

The `tokenProvider` closure is invoked on `401 Unauthorized` responses — the SDK calls back into your backend and retries the original request with the refreshed token.

---

## Components (v1.0)

| Component | Module | Status |
| --- | --- | --- |
| [PayIn](#payin) | `PayabliSDKPayIn` | ✅ Ships v1.0 |
| [Payout](#payout) | `PayabliSDKPayout` | ❌ Future |
| [Reporting](#reporting) | `PayabliSDKReporting` | ❌ Future |
| [Onboarding](#onboarding) | `PayabliSDKOnboarding` | ❌ Future |

---

## PayIn

Everything related to accepting payments. Exposed through `PayabliPayIn.shared` (singleton, `@MainActor`) for the UI-driven flows, and through `PayabliTTP` (instantiated directly) for Tap to Pay.

Four sub-flows:

1. [Tokenization](#tokenization-drop-in-ui) — save a card/ACH method for later use
2. [Getpaid](#getpaid-card-not-present-charge) — one-time authorize-and-capture with a card/ACH form or a stored method
3. [Apple Pay](#apple-pay) — present the Apple Pay sheet to tokenize or charge
4. [Tap to Pay on iPhone](#tap-to-pay-on-iphone) — card-present NFC acceptance (no external reader)

All four assume `PayabliPayIn.shared.configure(...)` has been called first (see [Authentication](#authentication)). Tap to Pay is the one exception — it takes its `accessToken` directly and does **not** require `PayabliPayIn.configure`.

---

### Tokenization (drop-in UI)

Present a SwiftUI form that validates, submits to `POST /api/TokenStorage/add`, and returns a reusable `methodReferenceId`.

```swift
let vc = PayabliPayIn.shared.createTokenizationViewController(
    type: .card,          // or .ach
    customerId: 4440
) { token, error in
    if let token {
        // persist token server-side for future charges
    } else if let error {
        // surface to user
    }
}

present(vc, animated: true)
```

The form respects the `PayabliTheme` you passed to `configure(...)`. Cancellation from the user surfaces as a `PayabliGenericError(code: .userCancelled)`.

---

### Getpaid (card-not-present charge)

Two variants — one with UI (form), one headless (stored method).

#### With UI

```swift
let request = PayabliPaymentRequest(
    totalAmount: 49.99,
    currency: "USD",
    orderId: "order-1234",
    saveIfSuccess: true  // tokenize after a successful charge
)

let vc = PayabliPayIn.shared.createPaymentViewController(
    type: .card,
    paymentRequest: request,
    customerId: 4440
) { result, error in
    // result.referenceId, result.methodReferenceId (when saveIfSuccess=true)
}

present(vc, animated: true)
```

#### Headless (stored method)

```swift
let request = PayabliPaymentRequest(
    totalAmount: 19.99,
    storedMethodId: savedMethodReferenceId
)

await PayabliPayIn.shared.chargeStoredMethod(
    methodType: .card,
    paymentRequest: request,
    customerId: 4440
) { result, error in
    // no UI presented; result is posted on the main actor
}
```

Stored-method charges default to `initiator: .merchant` for MIT compliance (PRD FR-12B.4). Override via `PayabliPaymentRequest.initiator` when appropriate.

---

### Apple Pay

Two modes share the same `PayabliApplePayConfig`: **Set Up** (tokenize for later) and **Pay** (authorize-and-capture now).

```swift
let applePayConfig = PayabliApplePayConfig(
    merchantIdentifier: "merchant.com.yourcompany.app",
    merchantName: "Your Merchant Name"
)
```

#### Set Up — tokenize Apple Pay

```swift
await PayabliPayIn.shared.setupApplePay(
    applePayConfig: applePayConfig,
    amount: 0.00,                  // zero-auth for pure tokenization
    customerId: 4440
) { token, error in
    // token is a Payabli methodReferenceId usable with chargeStoredMethod
}
```

#### Pay — charge Apple Pay

```swift
let request = PayabliPaymentRequest(totalAmount: 49.99, orderId: "order-5678")

await PayabliPayIn.shared.chargeApplePay(
    applePayConfig: applePayConfig,
    paymentRequest: request,
    customerId: 4440
) { result, error in
    // result has the transaction referenceId + processor response
}
```

Requires the `Apple Pay` capability enabled on your App ID and the merchant identifier registered with Apple.

---

### Tap to Pay on iPhone

Card-present NFC acceptance, no external reader. Lives in `PayabliTTP` (not on the `PayabliPayIn` singleton) because it holds per-device attestation state and a 9-state session lifecycle.

#### Prerequisites

1. **Device entitlement.** Request `com.apple.developer.proximity-reader.payment.acceptance` from Apple — this is an allowlisted entitlement, not automatically granted. [Apple docs](https://developer.apple.com/tap-to-pay-on-iphone/).
2. **App ID configuration.** Same bundle identifier must be enrolled with Apple's Tap to Pay program and with Payabli's partner onboarding.
3. **Device eligibility.** iPhone XS or later, iOS 16.7+, region supported by Tap to Pay, device unlocked. The SDK enforces this on `initialize()` (FR-11J.2).
4. **Payabli onboarding.** The merchant must have a Tap to Pay–enabled entry point (`entryPoint` string) provisioned by Payabli.

#### Lifecycle overview

```
.idle ─▶ .attestingDevice ─▶ .fetchingConfig ─▶ .initializingReader ─▶ .ready
                              │
                              └─▶ .pendingActivation ─▶ (partner provides code) ─▶ .idle
```

First launch runs **cold attestation** with Apple's App Attest + Payabli's `/register` / `/attest` endpoints. Later launches reuse the cached attestation and only refresh `/config`.

#### Integrate

```swift
import PayabliSDKPayIn

@MainActor
final class CheckoutViewModel: ObservableObject {
    let ttp: PayabliTTP
    private var eventsTask: Task<Void, Never>?

    init(accessToken: String, refresh: @escaping () async throws -> String) {
        self.ttp = PayabliTTP(
            accessToken: accessToken,
            tokenProvider: refresh,
            entry: "f743aed24a",
            appId: "TEAM123456.com.yourcompany.app",  // TEAMID.bundle-id
            environment: .sandbox
        )
        observeEvents()
    }

    deinit { eventsTask?.cancel() }

    private func observeEvents() {
        let stream = ttp.events()
        eventsTask = Task { [weak self] in
            for await event in stream {
                await self?.handle(event)
            }
        }
    }

    private func handle(_ event: PayabliTTPEvent) {
        switch event {
        case .attestationStarted:       print("Attesting device…")
        case .readerReady:              print("Reader is ready to tap")
        case .nfcStarted:               print("Hold card near iPhone…")
        case .nfcCompleted:             print("Card read, charging…")
        case .updateCompleted(let id):  print("Charge complete: \(id)")
        case .devicePendingActivation:  print("Ask admin for activation code")
        case .activationCompleted:      print("Device activated — re-run initialize()")
        default: break
        }
    }
}
```

#### Use

```swift
// 1. One-time (per session) startup.
try await viewModel.ttp.initialize()

// 2. Charge. Returns the paymentTransId; look up full details via the
//    Payabli API using that ID.
let result = try await viewModel.ttp.charge(
    amount: 9.99,
    type: .sale,
    customer: PayabliTTPCustomerData(firstName: "Jane", lastName: "Doe"),
    order: PayabliTTPOrderData(orderId: "order-9001")
)

print("paymentTransId:", result.paymentTransId)
```

#### Pending-device activation

If the merchant's device hasn't been activated yet, `initialize()` throws `.devicePendingActivation`:

```swift
do {
    try await viewModel.ttp.initialize()
} catch PayabliTTPError.devicePendingActivation {
    // Prompt the merchant for the OTP the partner delivered out-of-band.
    let code = await promptForActivationCode()
    try await viewModel.ttp.activateDevice(activationCode: code)
    try await viewModel.ttp.initialize()  // re-run after activation
}
```

The activation code is **partner-issued** — your admin dashboard calls Payabli's `/activate/challenge` endpoint server-side and delivers the OTP to the device user through your own channel. The SDK only consumes it, never requests it.

#### Observing state for UI bindings

`PayabliTTP` is an `ObservableObject`; `sessionState` and `isReady` are `@Published`:

```swift
@StateObject var vm: CheckoutViewModel

var body: some View {
    VStack {
        if vm.ttp.isReady {
            Button("Tap to Pay") { Task { try await vm.ttp.charge(amount: 9.99, type: .sale) } }
        } else {
            ProgressView("Session: \(String(describing: vm.ttp.sessionState))")
        }
    }
}
```

See [`Sources/PayabliSDKPayIn/TapToPay/README.md`](./Sources/PayabliSDKPayIn/TapToPay/README.md) for the full 9-state machine, event catalog, and adapter contract.

---

## Payout

Not available in v1.0. See [RFC-0001](./RFC-0001-payabli-sdk-ios.md) for roadmap.

---

## Reporting

Not available in v1.0. See [RFC-0001](./RFC-0001-payabli-sdk-ios.md) for roadmap.

---

## Onboarding

Not available in v1.0. See [RFC-0001](./RFC-0001-payabli-sdk-ios.md) for roadmap.

---

## Demo app

```bash
cd Example/PayabliDemo
cp Config.xcconfig.sample Config.xcconfig   # fill in sandbox credentials
open PayabliDemo.xcodeproj
```

## License

Commercial. See [LICENSE](./LICENSE).
