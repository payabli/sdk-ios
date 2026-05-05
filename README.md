# Payabli iOS SDK

Accept in-person card payments on iPhone with **Tap to Pay** — no card
reader required, just an iPhone running iOS 16.7 or newer.

```swift
import PayabliSDKTapToPay

let ttp = PayabliTTP(
    accessToken: token,
    tokenProvider: { try await yourBackend.fetchPayabliAccessToken() },
    entryPoint: "your-entry-point",
    appId: "TEAM123456.com.yourcompany.app",   // TEAMID.bundle-id
    environment: .sandbox
)

try await ttp.initialize()
let result = try await ttp.charge(amount: 9.99, type: .sale)
print("Got it! Transaction ID:", result.paymentTransId)
```

That's the whole happy path. The SDK takes care of device attestation,
session management, NFC reading, retries, and reconciling with Payabli's
backend — you write the checkout UI.

`PayabliTTP` is an `ObservableObject`, so you can bind `sessionState` and
`isReady` directly in SwiftUI, or subscribe to `events()` for fine-grained
progress updates.

---

## What you get

| Capability                    | Notes                                                    |
| ----------------------------- | -------------------------------------------------------- |
| Tap to Pay on iPhone          | Card-present NFC, no external reader needed.             |
| Swift **and** Objective-C API | First-class `@objc` surface for MAUI, Flutter, RN hosts. |
| Built-in App Attest           | Cold/warm device attestation, cached for you.            |
| Pending-device activation     | OTP flow for first-time devices, fully wired.            |
| Optional telemetry            | Plug in your own Sentry / PostHog if you want it.        |

**Requirements:** iOS 16.7+, iPhone XS or newer, Xcode 15+, Swift 5.9+
(Swift Package Manager 5.9+, bundled with Xcode 15).

---

## Pick the right module

The SDK ships as a few focused frameworks. Most apps only need
`PayabliSDKTapToPay`:

| Module                  | When to pick it                                                  |
| ----------------------- | ---------------------------------------------------------------- |
| `PayabliSDK`            | Umbrella — links Core + TapToPay together. Fine if you're unsure. |
| `PayabliSDKCore`        | Just the building blocks (config, auth, transport).              |
| `PayabliSDKTapToPay`    | Tap to Pay on iPhone. **This is the one you probably want.**     |
| `PayabliCardReaderCore` | The Tap to Phone engine — pulled in for you, no need to add it.  |
| `PayabliSDKTelemetry`   | Optional Sentry / PostHog plumbing. Bring your own instance.     |

---

## Install

### Swift Package Manager

In Xcode, choose **File → Add Packages…** and paste:

```
https://github.com/payabli/payabli-sdk-ios.git
```

Or add it to your `Package.swift`:

```swift
.package(url: "https://github.com/payabli/payabli-sdk-ios.git", from: "1.0.0")
```

Then link the product you need:

```swift
.product(name: "PayabliSDKTapToPay", package: "payabli-sdk-ios")
```

That's it — `PayabliSDKTapToPay` brings in the core and reader engine for
you.

---

## Configuration values

When you create `PayabliTTP`, you pass four values. Here's where each comes
from:

### `entryPoint`

The Payabli identifier for your merchant entry. Issued by Payabli when your
account is provisioned for Tap to Pay (e.g. `"acmePay"`). It's the same
slug you use to sign in to the dashboard at
`https://app.payabli.com/<entryPoint>/signin`.

### `appId`

Your iOS app's identity from Apple's perspective:
`<TEAM_ID>.<BUNDLE_ID>`.

- **`TEAM_ID`** — the 10-character team identifier from your
  [Apple Developer account](https://developer.apple.com/account)
  (Membership → Team ID).
- **`BUNDLE_ID`** — your app's bundle identifier from Xcode
  (Target → General → Bundle Identifier), e.g. `com.acme.checkout`.

Full example: `"TEAM123456.com.acme.checkout"`.

App Attest uses `appId` to prove that the binary on the device is the one
you registered — a mismatch surfaces as `attestationFailed` on
`initialize()`. The same `appId` must be authorized in the Payabli
dashboard (see [Before your first tap](#before-your-first-tap)).

### `environment`

Picks which Payabli API the SDK talks to:

| Value         | Base URL                          |
| ------------- | --------------------------------- |
| `.sandbox`    | `https://api-sandbox.payabli.com` |
| `.production` | `https://api.payabli.com`         |

Use `.sandbox` while developing and testing; switch to `.production` for
live merchant traffic. Match this with your App Attest entitlement —
`development` for sandbox builds, `production` for release builds.

### `accessToken` / `tokenProvider`

Short-lived bearer token from your backend, plus an `async` closure the SDK
calls to refresh it. Covered in [How auth works](#how-auth-works) below.

---

## How auth works

Your `clientSecret` never touches the device. Your backend exchanges it for
a short-lived `access_token`, and your app uses that:

```text
Mobile app  ──▶  Your backend  ──▶  Payabli (POST /api/v2/token/serverside)
            ◀──  access_token  ◀──
```

Pass the token (and a refresh callback) when you create `PayabliTTP`:

```swift
let ttp = PayabliTTP(
    accessToken: try await yourBackend.fetchPayabliAccessToken(),
    tokenProvider: { try await yourBackend.fetchPayabliAccessToken() },
    entryPoint: "your-entry-point",
    appId: "TEAM123456.com.yourcompany.app",
    environment: .sandbox
)
```

When the SDK sees a `401 Unauthorized`, it calls `tokenProvider`, gets a
fresh token, and quietly retries the request. Concurrent 401s are
deduplicated, so you don't have to worry about thundering-herd refreshes.

---

## Wiring up your backend (5-minute version)

Your `clientSecret` is like the master key to your Payabli account — it
should never live in the app. Instead, you stand up one tiny endpoint on
your own server that does the trade:

```text
   📱  iOS app           🖥️  Your backend           🔐  Payabli
   ───────────           ──────────────             ─────────
   "I need a token"  ──▶  "Swap this for a       ──▶  POST /api/v2/token/serverside
                          short-lived token"
                                                  ◀──  access_token
                     ◀── access_token  ◀──
```

That's the whole flow. The app talks to *your* backend; *your* backend
talks to Payabli. The secret never leaves your servers.

### A working example in ~30 lines of Node.js

Drop this into a Node project (`npm i express cors dotenv`) and you've got
a working token endpoint:

```js
// server.js
import "dotenv/config";
import express from "express";
import cors from "cors";

const app = express();
app.use(cors(), express.json());

const PAYABLI_URL = process.env.PAYABLI_URL || "https://api-sandbox.payabli.com/api";

app.post("/payabli/token", async (req, res) => {
  const { clientId, clientSecret } = req.body ?? {};
  if (!clientId || !clientSecret) {
    return res.status(400).json({ error: "clientId and clientSecret are required" });
  }

  const upstream = await fetch(`${PAYABLI_URL}/v2/token/serverside`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ clientId, clientSecret }),
  });

  res.status(upstream.status).json(await upstream.json());
});

app.listen(process.env.PORT || 3000, () =>
  console.log("Token server ready 🚀"));
```

That's it. Hit `POST /payabli/token` with your credentials and you'll get
an access token back, ready to hand to the iOS SDK.

> 💡 **Going to production?** Move `clientId` and `clientSecret` into
> environment variables on your server, and protect the endpoint with
> whatever auth your app already uses (session cookie, partner JWT, mTLS,
> etc.) — the example above keeps it simple on purpose.

### Calling it from iOS

The `tokenProvider` you pass to `PayabliTTP` is just an `async` closure
that returns a `String`. Plug your backend in like this:

```swift
func fetchPayabliAccessToken() async throws -> String {
    struct Response: Decodable { let access_token: String }

    var request = URLRequest(url: URL(string: "https://your-backend.example.com/payabli/token")!)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(Response.self, from: data).access_token
}
```

And you're done — pass it straight into the SDK:

```swift
let ttp = PayabliTTP(
    accessToken: try await fetchPayabliAccessToken(),
    tokenProvider: { try await fetchPayabliAccessToken() },
    entryPoint: "your-entry-point",
    appId: "TEAM123456.com.yourcompany.app",
    environment: .sandbox
)
```

The SDK will call `tokenProvider` again on its own whenever the token
expires. You don't have to track expirations, schedule refreshes, or
debounce anything — it just works.

---

## Before your first tap

A few one-time setup steps with Apple and Payabli:

1. **Apple entitlement.** Request `com.apple.developer.proximity-reader.payment.acceptance`
   from Apple — it's allowlisted, not granted automatically. Apple's
   [Setting Up the Entitlement](https://developer.apple.com/documentation/proximityreader/setting-up-the-entitlement-for-tap-to-pay-on-iphone)
   guide walks you through it.
2. **App Attest entitlement.** Add `com.apple.developer.devicecheck.appattest-environment`
   set to `production` (or `development` for dev builds). Match this with
   the `environment` you pass to the SDK (see
   [Configuration values](#configuration-values)).
3. **Authorize the app in the Payabli dashboard.** Sign in at
   `https://app.payabli.com/<entryPoint>/signin`, open
   **Settings → Devices**, click **Authorized Apps**, and add the same
   `appId` (`<TEAM_ID>.<BUNDLE_ID>`) you'll pass to the SDK. Until the app
   is authorized here, attestation will be rejected on `initialize()`.
4. **Eligible device.** iPhone XS or newer, iOS 16.7+, supported region,
   unlocked. The SDK will check this for you on `initialize()`.
5. **Entry point.** Have Payabli provision a Tap to Pay-enabled entry point
   for you.

---

## The session lifecycle

Here's what happens behind the scenes:

```
.idle ─▶ .attestingDevice ─▶ .fetchingConfig ─▶ .initializingReader ─▶ .ready
                              │
                              └─▶ .pendingActivation ─▶ (partner OTP) ─▶ .idle

.ready ─▶ .sessionExpired ─▶ .reinitializing ─▶ .fetchingConfig ─▶ .initializingReader ─▶ .ready
```

The first launch does **cold attestation** (Apple's App Attest plus
Payabli's `/register` and `/attest` endpoints). Subsequent launches reuse
the cached attestation and just refresh `/config`, so they're much faster.

---

## A complete example

```swift
import PayabliSDKTapToPay

@MainActor
final class CheckoutViewModel: ObservableObject {
    let ttp: PayabliTTP

    init(accessToken: String, refresh: @escaping () async throws -> String) {
        self.ttp = PayabliTTP(
            accessToken: accessToken,
            tokenProvider: refresh,
            entryPoint: "your-entry-point",
            appId: "TEAM123456.com.yourcompany.app",
            environment: .sandbox
        )
    }
}

// 1. Once per session — this can take a few seconds on a cold start.
try await viewModel.ttp.initialize()

// 2. Take the payment.
let result = try await viewModel.ttp.charge(
    amount: 9.99,
    type: .sale,
    customer: PayabliTTPCustomerData(firstName: "Jane", lastName: "Doe"),
    order: PayabliTTPOrderData(orderId: "order-9001")
)

print("Payment captured! ID:", result.paymentTransId)
```

`charge(amount:type:serviceFee:customer:order:)` runs three steps:
`POST /MoneyIn/initiate` → NFC tap → `PATCH /MoneyIn/update/{id}`. If the
final update fails after retries, the transaction is still authorized on
the processor side — you'll need to reconcile manually (this is rare).

### What `charge(...)` accepts

```swift
public func charge(
    amount: Decimal,
    type: PayabliTTPPaymentType,
    serviceFee: Decimal = 0,
    customer: PayabliTTPCustomerData = .init(),
    order: PayabliTTPOrderData = .init()
) async throws -> TransactionResult
```

| Parameter    | Type                       | Required | Notes                                                                                       |
| ------------ | -------------------------- | -------- | ------------------------------------------------------------------------------------------- |
| `amount`     | `Decimal`                  | yes      | Total amount to charge in the merchant's currency (e.g. `9.99`).                            |
| `type`       | `PayabliTTPPaymentType`    | yes      | v1.0 supports `.sale` only.                                                                 |
| `serviceFee` | `Decimal`                  | no       | Optional convenience fee added on top of `amount`. Defaults to `0`.                         |
| `customer`   | `PayabliTTPCustomerData`   | no       | Cardholder/customer snapshot. Persisted at `/initiate`. Defaults to an empty (anonymous) customer. |
| `order`      | `PayabliTTPOrderData`      | no       | Order/invoice metadata. Persisted at `/initiate`.                                           |

`PayabliTTPCustomerData` (every field optional, blank values are
ignored):

| Field             | Type      | Purpose                                                                |
| ----------------- | --------- | ---------------------------------------------------------------------- |
| `firstName`       | `String?` | Cardholder first name.                                                 |
| `lastName`        | `String?` | Cardholder last name.                                                  |
| `customerNumber`  | `String?` | Your internal customer reference, surfaced on the Payabli transaction. |
| `email`           | `String?` | Customer email for receipts / reconciliation.                          |
| `phone`           | `String?` | Customer phone, free-form.                                             |

`PayabliTTPOrderData` (every field optional):

| Field              | Type      | Purpose                                                                                            |
| ------------------ | --------- | -------------------------------------------------------------------------------------------------- |
| `orderId`          | `String?` | Your order identifier; also used as the fallback invoice number when `invoiceNumber` is `nil`.     |
| `orderDescription` | `String?` | Human-readable description of the order.                                                           |
| `invoiceNumber`    | `String?` | Invoice reference passed to the processor. Falls back to `orderId` if `nil`.                       |

```swift
let result = try await ttp.charge(
    amount: 24.50,
    type: .sale,
    serviceFee: 1.00,
    customer: PayabliTTPCustomerData(
        firstName: "Jane",
        lastName: "Doe",
        customerNumber: "cust-1234",
        email: "jane@example.com",
        phone: "+1 555 0100"
    ),
    order: PayabliTTPOrderData(
        orderId: "order-9001",
        orderDescription: "Two coffees + croissant",
        invoiceNumber: "INV-9001"
    )
)
```

---

## Listening for events

If you want a play-by-play of what the session is doing — to drive a
spinner, log analytics, or update UI — subscribe to `events()`:

```swift
for await event in viewModel.ttp.events() {
    switch event {
    case .readerReady:              print("Ready to tap!")
    case .nfcStarted:               print("Hold card near iPhone…")
    case .updateCompleted(let id):  print("Charge complete: \(id)")
    case .devicePendingActivation:  print("Ask admin for activation code")
    default: break
    }
}
```

Multiple subscribers all receive every event — go nuts.

---

## Pending device activation

The very first time a device runs your app, it may need an activation code
before it can take payments. `initialize()` will throw
`.devicePendingActivation` to let you know:

```swift
do {
    try await ttp.initialize()
} catch PayabliTTPError.devicePendingActivation {
    let code = await promptForActivationCode()        // your UI
    try await ttp.activateDevice(activationCode: code)
    try await ttp.initialize()                        // try again
}
```

The activation code is issued by your partner backend (typically your admin
dashboard), not by the SDK. You deliver it to the user through whatever
channel makes sense for your business. The SDK just consumes it.

---

## Objective-C, MAUI, Flutter, React Native

The SDK is bilingual. Every Swift `async throws` method has a
callback-based `@objc` companion, structs have `*ObjC` companion classes,
events expose stable integer codes, and errors bridge to `NSError` with
domain `"com.payabli.ttp"`.

```objc
PayabliTTP *ttp = [[PayabliTTP alloc]
    initWithAccessToken:token
    tokenRefreshHandler:^(void (^done)(NSString *, NSError *)) { /* ... */ }
              entryPoint:@"your-entry-point"
                   appId:@"TEAM123456.com.yourcompany.app"
             environment:PayabliEnvironmentSandbox];

[ttp initializeWithCompletion:^(NSError *err) {
    if (err) { /* handle */ return; }
    [ttp chargeWithAmount:[NSDecimalNumber decimalNumberWithString:@"9.99"]
                     type:PayabliTTPPaymentTypeSale
               serviceFee:NSDecimalNumber.zero
                 customer:nil
                    order:nil
               completion:^(PayabliTTPTransactionResultObjC *result, NSError *e) {
        NSLog(@"Got it! ID: %@", result.paymentTransId);
    }];
}];
```

Cross-platform host code lives under `Bridges/Flutter/`, `Bridges/MAUI/`,
and `Bridges/ReactNative/`. See [Bridges/README.md](./Bridges/README.md) for
the current status of each.

---

## Handling errors

`PayabliTTPError` covers the whole session and charge lifecycle, so you can
match exactly the cases you care about:

```swift
do {
    try await ttp.initialize()
    let result = try await ttp.charge(amount: 9.99, type: .sale)
} catch PayabliTTPError.devicePendingActivation {
    // First-time device — prompt for activation code.
} catch let PayabliTTPError.invalidState(current, attempted) {
    // Session isn't in the right state for this call.
} catch let PayabliTTPError.attestationFailed(reason) {
    // App Attest or Payabli refused to attest this device.
} catch let PayabliTTPError.nfcFailed(reason) {
    // Card removed too soon, reader timeout, etc. — usually retryable.
} catch let PayabliTTPError.updateFailed(reason) {
    // /update PATCH failed after retries. Reconcile manually.
} catch PayabliTTPError.tokenExpired {
    // tokenProvider returned nothing — re-auth required.
}
```

If you're using the SDK from Objective-C or a bridged framework, you'll see
these as `NSError` instances with domain `"com.payabli.ttp"` and a stable
per-case integer code.

---

## Try it out

A complete SwiftUI sample app — initialize, charge, activate, live event
log — is in [`Example/PayabliDemo`](./Example/PayabliDemo/):

```bash
cd Example/PayabliDemo
cp Secrets.swift.sample Secrets.swift    # fill in your sandbox credentials
```

Tap to Pay only works on a real iPhone XS (or newer) running iOS 16.7+.
Simulators won't pass the eligibility check.

---

## Support

- Bug reports and feature requests: **support@payabli.com**
- Integration docs: **<https://docs.payabli.com/ios>**

---

## License

Commercial — see [LICENSE](./LICENSE). The bundled
`PayabliCardReaderCore` engine is MIT-licensed; full attribution lives in
`THIRD_PARTY_LICENSES.txt`.
