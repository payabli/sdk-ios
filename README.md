# Payabli iOS SDK

The Payabli iOS SDK lets an iPhone app take payments through Payabli in two ways:

- **Card-not-present.** Your app collects card or bank account details, in the SDK's SwiftUI form or in
  your own UI, and the SDK stores them as a payment method or charges them.
- **Tap to Pay on iPhone.** The payer taps a contactless card, phone or watch on the iPhone, with no
  external reader.

Your app never holds your Payabli client ID or client secret. It supplies a function that fetches a
short-lived access token from your backend, and the SDK calls it when it needs one. The SDK holds that
token in memory while the session runs.

[Payabli developer documentation](https://docs.payabli.com/guides/mobile-components-overview) ·
[Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md) · [Sample app](Example/PayabliDemo/)

> **No version has been released yet.** See [Versioning and support](#versioning-and-support).

## Key terms

| Term | Meaning |
|---|---|
| **Paypoint** | A merchant account in Payabli. Payments are made to a paypoint. |
| **Entry point** | The identifier of a paypoint, for example `acmePay`. You pass it to the SDK. Payabli gives it to you, and it is also the path in the paypoint's portal address, `https://app.payabli.com/<entryPoint>/signin`. |
| **Token endpoint** | A route on your own backend that exchanges your Payabli client ID and client secret for a short-lived access token and returns the token to your app. |
| **Allowlist** | The list of apps a paypoint accepts Tap to Pay requests from. |

## Modules

| Product | Use it for | Guide |
|---|---|---|
| `PayabliSDKPayIn` | Card-not-present | [Card-not-present payments](#card-not-present-payments) |
| `PayabliSDKTapToPay` | Tap to Pay | [`Sources/PayabliSDKTapToPay/README.md`](Sources/PayabliSDKTapToPay/README.md) |
| `PayabliSDK` | Both | |

Every product includes `PayabliSDKCore`, which holds the configuration types. Import it by name where you
use them.

## Requirements

| | Requirement |
|---|---|
| iOS | 16.7 or later |
| Toolchain | Xcode 15 or later, Swift 5.9 or later |
| Tap to Pay | A physical iPhone XS or newer. See [the Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md#requirements). Card-not-present runs in the simulator |

## Before you start

1. **Get a sandbox paypoint.** Ask your Payabli representative for a sandbox entry point, with Tap to Pay
   enabled if you plan to use it.
2. **Create OAuth2 credentials.** Provision a client ID and client secret for the sandbox. See
   [OAuth authentication](https://docs.payabli.com/developers/oauth-authentication).
   - Card-not-present needs `inboundpayments_create` to charge, authorize and capture,
     `inboundpayments_void` to void, and `tokens_create` to store a payment method.
   - Tap to Pay needs `tools_init`, `pos_create` and `inboundpayments_create`.
3. **Build your token endpoint.** See [Build your token endpoint](#build-your-token-endpoint).
4. **For Tap to Pay only:** request Apple's Tap to Pay entitlement, and register the app on the paypoint's
   allowlist. See [the Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md#before-you-start).

## Installation

### Add the SDK

No version is tagged, so add the package by branch or by commit. In Xcode, choose
**File > Add Package Dependencies** and enter the repository URL:

```text
https://github.com/payabli/sdk-ios.git
```

Or declare it in `Package.swift`, tracking `main` or pinned to one commit:

```swift
.package(url: "https://github.com/payabli/sdk-ios.git", branch: "main")
.package(url: "https://github.com/payabli/sdk-ios.git", revision: "<commit SHA>")
```

In Xcode, the same choice is the **Branch** or **Commit** dependency rule.

Then link the products you need, from [Modules](#modules). Link `PayabliSDK` alone, or one or both of the
capability products. Linking `PayabliSDK` together with a capability product fails to build.

### Configure your app

Card-not-present needs no app configuration. Tap to Pay needs two entitlements, in
[the Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md#before-you-start).

## Get started

### Build your token endpoint

Your backend holds the client ID and client secret. It calls `POST /api/v2/token/serverside` with them
and returns the access token to your app. The client secret never reaches the device.

This example needs Node.js 18 or later and `"type": "module"` in `package.json`. It returns the token as
`{ "accessToken": "..." }`:

```js
// server.js
import express from "express";

const app = express();
const PAYABLI_URL = process.env.PAYABLI_URL ?? "https://api-sandbox.payabli.com/api";

app.post("/payabli/token", async (req, res) => {
  // authenticateUser is your app's own check of the caller's session. Never return a token without it.
  const user = await authenticateUser(req);
  if (!user) {
    return res.status(401).json({ error: "unauthenticated" });
  }
  const upstream = await fetch(`${PAYABLI_URL}/v2/token/serverside`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      clientId: process.env.PAYABLI_CLIENT_ID,
      clientSecret: process.env.PAYABLI_CLIENT_SECRET,
    }),
  });
  const body = await upstream.json();
  const accessToken = body.access_token ?? body.accessToken;
  if (!upstream.ok || !accessToken) {
    return res.status(502).json({ error: "token exchange failed" });
  }
  res.json({ accessToken });
});

app.listen(process.env.PORT ?? 3000);
```

Anyone who can call the route gets a token for your paypoint, so it has to authenticate the caller the way
the rest of your app does. The sample app ships a complete token server in
[`Example/PayabliDemo/LocalTokenServer`](Example/PayabliDemo/LocalTokenServer/README.md).

### Configure the SDK

Both modules need your entry point, the environment and a token provider. `PayabliPayIn` takes them as a
`PayabliConfig`, below. `PayabliTTP` takes them directly, with your app ID; see
[the Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md#create-the-tap-to-pay-session).

```swift
import PayabliSDKCore

let config = try PayabliConfig(
    entryPoint: "your-entry-point",
    environment: .sandbox,
    tokenProvider: { try await fetchPayabliAccessToken() }
)
```

| Environment | API host |
|---|---|
| `.sandbox` | `https://api-sandbox.payabli.com` |
| `.production` | `https://api.payabli.com` |

- `PayabliConfig` throws when the entry point is blank.

The token provider is an `async throws` function that returns a new access token from your token
endpoint:

```swift
func fetchPayabliAccessToken() async throws -> String {
    struct Response: Decodable { let accessToken: String }

    var request = URLRequest(url: URL(string: "https://your-backend.example.com/payabli/token")!)
    request.httpMethod = "POST"
    // Your app's own session credential, which your token endpoint verifies.
    request.setValue("Bearer \(yourSessionToken)", forHTTPHeaderField: "Authorization")
    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(Response.self, from: data).accessToken
}
```

- The SDK calls the provider before its first request, and again when a token is rejected.
- Concurrent callers share one call.
- Each call has 30 seconds to return. A call that takes longer, throws, or returns a token the SDK can't
  use fails with `PayabliErrorCode.tokenProviderFailed`.
- Return a token. Don't make SDK calls from inside the provider.

## Card-not-present payments

`PayabliPayIn` runs on a `PayabliSession` built from your configuration. It is `@MainActor`.

```swift
import PayabliSDKCore
import PayabliSDKPayIn

let payIn = PayabliPayIn(
    session: PayabliSession(config: config),
    operation: .capture,
    requestConfiguration: PayabliPayInRequestConfiguration(
        paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34)
    )
)
```

### Use the SDK's form

`PayabliPayInView` renders a card and bank account form and submits it with the operation you chose.
`operation` says what a submission does:

```swift
import SwiftUI
import PayabliSDKPayIn

struct CheckoutView: View {
    let payIn: PayabliPayIn

    var body: some View {
        PayabliPayInView(
            component: payIn,
            onCompleted: { result in /* charged, or saved */ },
            onError: { error in /* see Outcomes */ }
        )
    }
}
```

| Operation | What happens |
|---|---|
| `.storePaymentMethod` | Saves the card or bank account as a stored payment method. The default. |
| `.capture` | Charges the payment method. |
| `.authorize` | Authorizes a card without capturing it. |

To show the form in a sheet, use `.payabliPayInSheet(isPresented:component:configuration:sheetConfiguration:style:onCompleted:onError:)`.
`PayabliPayInFormConfiguration` chooses the payment methods and fields, and `PayabliPayInStyle` sets the
look.

### Call the API from your own UI

```swift
let result = try await payIn.capture(
    PayabliPayInRequest(
        paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34),
        paymentMethod: .card(.init(data: PayabliPayInCardData(
            cardNumber: "4012000098765439",
            expiration: "12/30",
            cardholderName: "Jane Doe",
            cvv: "999",
            billingZip: "12345"
        )))
    )
)
order.paymentTransId = result.transaction?.paymentTransId // store it; don't log it
```

Use Payabli's sandbox [test cards](https://docs.payabli.com/guides/test-accounts-reference) in sandbox.

| Method | What it does |
|---|---|
| `capture(_:)` | Charges a card, bank account or stored payment method. |
| `authorize(_:)` | Authorizes a card or stored card. |
| `captureAuthorizedTransaction(_:)` | Captures an earlier authorization. |
| `voidTransaction(_:)` | Voids a transaction that hasn't settled. |
| `addCard(_:options:)`, `addBankAccount(_:options:)`, `addPaymentMethod(_:options:)` | Saves a payment method and returns its stored ID. |

To charge a saved method, pass `.stored(.init(method: .card, storedMethodId: id))` as the payment method.

A charge always sends an idempotency key. The SDK mints one per call when you don't set
`PayabliPayInRequest.idempotencyKey`, so calling again without your own key is a second payment, not a
retry. Don't resend a charge whose outcome is unknown. Find the transaction first.

More detail: [`Documentation/PayInOverview.md`](Documentation/PayInOverview.md) and
[`Documentation/PayInIntegrationGuide.md`](Documentation/PayInIntegrationGuide.md).

## Tap to Pay payments

`PayabliTTP` builds its own session from your entry point and app ID. After the setup in
[the Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md), a payment takes three calls:

```swift
import PayabliSDKTapToPay

let ttp = try PayabliTTP(
    tokenProvider: { try await fetchPayabliAccessToken() },
    entryPoint: "your-entry-point",
    appId: "TEAM123456.com.example.checkout",
    environment: .sandbox
)
try await ttp.initialize()
let result = try await ttp.charge(
    type: .sale,
    paymentDetails: PayabliTTPPaymentDetails(amount: 9.99),
    customer: PayabliTTPCustomerData(firstName: "Jane", lastName: "Doe")
)
```

The guide covers the entitlements, the allowlist, activating a phone, Apple's terms, charging and errors.

## Outcomes

Every charge ends in one of these outcomes. Only **not charged** is safe to retry.

| Outcome | Card-not-present | Tap to Pay | Retry? |
|---|---|---|---|
| **Charged** | The call returns a result | `charge` returns a `TransactionResult` | No |
| **Not charged** | `PayabliPayInError.transactionFailed`, for example a decline | an error whose `capture` is `.notCharged` | Yes |
| **Unknown** | `PayabliPayInError.submissionInterrupted` | an error whose `capture` is `.unknown` | Not until you've checked |
| **Charged, not confirmed** | — | an error whose `capture` is `.charged` | No. Reconcile the payment |

On card-not-present, the other errors mean nothing was charged: `invalidInput`, `missingAccessToken` and
`submissionInProgress` are refused before anything is sent, and a core error such as a validation
failure, a refused credential or a rate limit is the service's answer.

When the outcome is unknown, look the transaction up from your backend with
[`GET /api/MoneyIn/details/{transId}`](https://docs.payabli.com/developers/api-reference/moneyin/get-details-for-a-processed-transaction)
before you charge again. `PayabliPayInError.submissionInterrupted` carries no transaction ID, so set
`orderId` on each request and find the transaction by it in the Payabli portal. When a Tap to Pay error
carries no transaction ID, find the transaction in the portal. Store the transaction ID with your order
every time you get one.

## Language support

The SDK is written in Swift, and the card-not-present form is a SwiftUI view.

- **Objective-C.** `PayabliTTP` has an `@objc` companion, taking a completion handler, for every `async`
  method. Construct it with `initWithTokenHandler:entryPoint:appId:environment:error:`. Its errors bridge
  to `NSError` in the `com.payabli.ttp` domain: `userInfo["capture"]` holds the `PayabliTTPCapture` raw
  value (`0` not charged, `1` unknown, `2` charged), and `userInfo["paymentTransId"]` is absent when there
  is no transaction ID. For card-not-present, Objective-C uses `PayabliPayInObjC`, built with
  `initWithTokenHandler:entryPoint:environment:error:`, which offers `addCard` and `addBankAccount`.
- **Flutter, .NET MAUI and React Native.** Wrappers are in [`Bridges/`](Bridges/README.md), which lists the
  status of each.

## Sample app

[`Example/PayabliDemo`](Example/PayabliDemo/) is a SwiftUI app that runs card-not-present and Tap to Pay
against your sandbox paypoint, with a bundled token server.

```bash
git clone https://github.com/payabli/sdk-ios.git
cd sdk-ios/Example/PayabliDemo
cp App/Configuration/Secrets.swift.sample App/Configuration/Secrets.swift
```

Fill in `Secrets.swift`, then start the token server as its
[README](Example/PayabliDemo/LocalTokenServer/README.md) describes.

## Privacy and data collection

The SDK sends no error or usage reports to Payabli. `PayabliConfig` accepts `telemetryEnabled`, which
changes nothing.

## Versioning and support

No version of the SDK has been released, and the repository has no tags. Until one is, add the package
by branch or by commit as [Installation](#installation) describes. `main` changes without notice, so a
build that tracks `main` picks up whatever is there when the package resolves. Use the commit rule for a
fixed build. This section gives the version to depend on once a release exists.

## Support

- Payabli developer documentation: <https://docs.payabli.com/guides/mobile-components-overview>
- Support: support@payabli.com

## License

Commercial. See [LICENSE](LICENSE). The bundled card reader engine is MIT-licensed; attribution is in
[`THIRD_PARTY_LICENSES.txt`](THIRD_PARTY_LICENSES.txt).
