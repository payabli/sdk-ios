# Payabli iOS SDK

The Payabli iOS SDK lets an iPhone app take payments through Payabli in two ways:

- **Card-not-present.** Your app collects card or bank account details, in the SDK's form or in your own
  UI, and the SDK stores them as a payment method or charges them. This is the `PayabliSDKPayIn`
  module.
- **Tap to Pay on iPhone.** The payer taps a contactless card, phone or watch on the iPhone, with no
  external reader. This is the `PayabliSDKTapToPay` module, documented in
  [`Sources/PayabliSDKTapToPay/README.md`](Sources/PayabliSDKTapToPay/README.md).

Your app never holds your Payabli client ID or client secret. It supplies a function that fetches a
short-lived access token from your backend, and the SDK calls it when it needs one. The SDK holds that
token in memory while the session runs.

## Terms used in this guide

| Term | Meaning |
|---|---|
| **Paypoint** | A merchant account in Payabli. Payments are made to a paypoint. |
| **Entry point** | The identifier of a paypoint, for example `acmePay`. You pass it to the SDK. Payabli gives it to you, and it is also the path in the paypoint's portal address, `https://app.payabli.com/<entryPoint>/signin`. |
| **Token endpoint** | A route on your own backend that exchanges your Payabli client ID and client secret for a short-lived access token and returns the token to your app. |
| **Allowlist** | The list of apps a paypoint accepts Tap to Pay requests from. |

## Requirements

- iOS 16.7 or later.
- Xcode 15 or later and Swift 5.9 or later.
- A physical iPhone XS or newer for Tap to Pay. Card-not-present runs in the simulator.

## Before you write code

1. **Get a sandbox paypoint.** Ask your Payabli representative for a sandbox entry point, with Tap to Pay
   enabled if you plan to use it.
2. **Create OAuth2 credentials.** Provision a client ID and client secret for the sandbox. See
   [OAuth authentication](https://docs.payabli.com/developers/oauth-authentication). Tap to Pay needs the
   `tools_init`, `pos_create` and `inboundpayments_create` permissions, listed in
   [Accept Tap to Pay payments](https://docs.payabli.com/guides/pay-in-developer-tap-to-pay#permissions).
   Card-not-present needs `inboundpayments_create` to charge, authorize and capture, `inboundpayments_void`
   to void, and `tokens_create` to store a payment method.
3. **Build your token endpoint.** See [Build your token endpoint](#build-your-token-endpoint).
4. **For Tap to Pay only:** request Apple's Tap to Pay entitlement and register your app on the
   paypoint's allowlist. See the
   [Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md#before-you-write-code).

## Install

**No version of the SDK has been released yet.** The repository has no tags, so the only way to add the
package today is from the `main` branch. Your build picks up whatever is on `main` when the package
resolves. Pin a commit in `Package.resolved` if you need a fixed build.

In Xcode, choose **File > Add Package Dependencies**, enter the repository URL, and choose the `main`
branch:

```text
https://github.com/payabli/sdk-ios.git
```

Or declare it in `Package.swift`:

```swift
.package(url: "https://github.com/payabli/sdk-ios.git", branch: "main")
```

Then link the products you need:

| Product | Link it for |
|---|---|
| `PayabliSDKPayIn` | Card-not-present |
| `PayabliSDKTapToPay` | Tap to Pay |
| `PayabliSDK` | Both |

Link `PayabliSDK` alone, or one or both of the capability products. Linking `PayabliSDK` together with a
capability product fails to build. Every product includes `PayabliSDKCore`, which holds the
configuration types. Import it by name where you use them.

## Build your token endpoint

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

Protect the route with the same authentication your app already uses. Anyone who can call it gets a
token for your paypoint.

The sample app ships a complete token server in
[`Example/PayabliDemo/LocalTokenServer`](Example/PayabliDemo/LocalTokenServer/README.md).

## Configure the SDK

Both modules need your entry point, the environment and a token provider. `PayabliPayIn` takes them as a
`PayabliConfig`, below. `PayabliTTP` takes them directly, with your app ID; see the
[Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md#create-the-tap-to-pay-session).

```swift
import PayabliSDKCore

let config = try PayabliConfig(
    entryPoint: "your-entry-point",
    environment: .sandbox,
    tokenProvider: { try await fetchPayabliAccessToken() }
)
```

`PayabliConfig` throws when the entry point is blank.

| Environment | API host |
|---|---|
| `.sandbox` | `https://api-sandbox.payabli.com` |
| `.production` | `https://api.payabli.com` |

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

`operation` says what a form submission does:

| Operation | What happens |
|---|---|
| `.storePaymentMethod` | Saves the card or bank account as a stored payment method. The default. |
| `.capture` | Charges the payment method. |
| `.authorize` | Authorizes a card without capturing it. |

### Use the SDK's form

`PayabliPayInView` renders a card and bank account form and submits it with the operation you chose:

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
print("Charged:", result.transaction?.paymentTransId ?? "")
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

See [`Sources/PayabliSDKTapToPay/README.md`](Sources/PayabliSDKTapToPay/README.md). It covers the Apple
entitlement, the allowlist, device activation, Apple's terms, charging and errors.

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
carries no transaction ID, find the transaction in the portal. Store the transaction ID with your order every time you get one.

## Objective-C and cross-platform apps

`PayabliTTP` has an `@objc` companion, taking a completion handler, for every `async` method, and its errors
bridge to `NSError`. For card-not-present, Objective-C uses `PayabliPayInObjC`, built with
`initWithTokenHandler:entryPoint:environment:error:`, which offers `addCard` and `addBankAccount`. Wrappers for Flutter, .NET MAUI and React Native are in [`Bridges/`](Bridges/README.md), which
lists the status of each.

## Sample app

[`Example/PayabliDemo`](Example/PayabliDemo/) is a SwiftUI app that runs both card-not-present and Tap to
Pay against your sandbox paypoint, with a bundled token server.

```bash
git clone https://github.com/payabli/sdk-ios.git
cd sdk-ios/Example/PayabliDemo
cp App/Configuration/Secrets.swift.sample App/Configuration/Secrets.swift
```

Fill in `Secrets.swift`, then start the token server as its
[README](Example/PayabliDemo/LocalTokenServer/README.md) describes.

## Support

- Payabli developer documentation: <https://docs.payabli.com/guides/mobile-components-overview>
- Support: support@payabli.com

## License

Commercial. See [LICENSE](LICENSE). The bundled card reader engine is MIT-licensed; attribution is in
`THIRD_PARTY_LICENSES.txt`.
