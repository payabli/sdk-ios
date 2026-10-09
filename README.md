# Payabli iOS SDK

The Payabli iOS SDK lets your iPhone app take payments through Payabli. Set it up once, and take a payment
either way: **card-not-present**, with card or bank account details entered in the SDK's SwiftUI form or
in your own UI, or **Tap to Pay on iPhone**, with a contactless card, phone or watch tapped on the iPhone.

Your app never holds your Payabli client ID or client secret. It supplies a function that fetches a
short-lived access token from your backend, and the SDK calls it when it needs one. The SDK holds that
token in memory while the session runs.

[Payabli developer documentation](https://docs.payabli.com/guides/mobile-components-overview) ·
[Card-not-present guide](Sources/PayabliSDKPayIn/README.md) ·
[Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md) · [Sample app](Example/PayabliDemo/)

> [!IMPORTANT]
> **Notice:** This SDK is in beta and under active development. Its public interface can change in ways that
> aren't backward compatible, including the names, parameters and behavior of its types and methods.
> No stable version has been released. See [Versioning and support](#versioning-and-support).

## How it works

1. **Your backend** exchanges your Payabli client ID and client secret for a short-lived access token,
   through a token endpoint you build.
2. **Your app** starts one session with your entry point, the environment and a token provider that calls
   that endpoint.
3. **On that session**, your app takes a payment card-not-present with `PayabliPayIn`, or card-present
   with `PayabliTTP`.
4. **Every charge ends in an outcome** your app acts on: charged, not charged, or unknown and to be
   reconciled.

### Key terms

| Term | Meaning |
|---|---|
| **Paypoint** | A merchant account in Payabli. Payments are made to a paypoint. |
| **Entry point** | The identifier of the paypoint the SDK takes payments for, for example `acmePay`. Payabli generates it. In the Payabli portal, it's the **Entry Name** column under **Portfolio > Paypoints**, and the List paypoints endpoint returns it as `EntryName`. Use the paypoint's entry point, not your organization's. Your organization's credentials work for every paypoint under it. An entry point exists in one environment. |
| **Token endpoint** | A route on your own backend that exchanges your Payabli client ID and client secret for a short-lived access token and returns the token to your app. |
| **Authorized apps** | The apps a paypoint accepts Tap to Pay requests from. The Payabli portal lists them under **Authorized apps**. |

## Requirements

| | Requirement |
|---|---|
| iOS | 16.7 or later |
| Toolchain | Xcode 15 or later, Swift 5.9 or later |
| Tap to Pay | A physical iPhone XS or newer. See the [Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md#requirements). Card-not-present runs in the simulator |

## Installation

### Add the SDK

Add the package with Swift Package Manager, tracking the `main` branch, which is the recommended
setup. In Xcode, choose **File > Add Package Dependencies**, enter the repository URL, and choose the
**Branch** rule with `main`:

```text
https://github.com/payabli/sdk-ios.git
```

Or declare it in `Package.swift`:

```swift
.package(url: "https://github.com/payabli/sdk-ios.git", branch: "main")
```

To build the same code every time, pin one commit instead, with Xcode's **Commit** rule or:

```swift
.package(url: "https://github.com/payabli/sdk-ios.git", revision: "<commit SHA>")
```

Then link what you use:

| Product | Adds |
|---|---|
| `PayabliSDKPayIn` | Card-not-present |
| `PayabliSDKTapToPay` | Tap to Pay |
| `PayabliSDK` | Both |

Link `PayabliSDK` alone, or one or both of the others. Linking `PayabliSDK` together with either fails to
build. Each includes `PayabliSDKCore`, which holds the configuration types; import it by name where you use
them.

### Configure your app

Card-not-present needs no app configuration. Tap to Pay needs two entitlements, in the
[Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md#before-you-start).

## Set up the SDK

### Prepare your Payabli account

1. **Get a sandbox paypoint.** Ask your Payabli representative for a sandbox entry point, with Tap to Pay
   enabled if you plan to use it.
2. **Create OAuth2 credentials.** Provision a client ID and client secret for the sandbox. See
   [OAuth authentication](https://docs.payabli.com/developers/oauth-authentication).
   Give them the permissions in the table below.
3. **For Tap to Pay**, request Apple's entitlement and register the app as one of the paypoint's authorized apps, as
   the [Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md#before-you-start) describes.

Each operation needs its own permission on those credentials:

| Operation | Permission |
|---|---|
| Charge, authorize, or capture an authorization | `inboundpayments_create` |
| Void a transaction | `inboundpayments_void` |
| Save a payment method | `tokens_create` |
| Initialize Tap to Pay on a phone | `tools_init` and `pos_create` |
| Activate a phone with its code | `tools_init` and `pos_create` |
| Take a Tap to Pay payment | `inboundpayments_create` |
| Register an authorized app through the API | `pos_create` |

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
  // mayTakePayments is your app's own rule for who may take payments for this paypoint.
  if (!(await mayTakePayments(user))) {
    return res.status(403).json({ error: "forbidden" });
  }
  let accessToken;
  try {
    const upstream = await fetch(`${PAYABLI_URL}/v2/token/serverside`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        clientId: process.env.PAYABLI_CLIENT_ID,
        clientSecret: process.env.PAYABLI_CLIENT_SECRET,
      }),
      redirect: "error", // never replay the client secret to another origin
      signal: AbortSignal.timeout(10_000), // well inside the SDK's 30 seconds
    });
    const body = await upstream.json();
    accessToken = upstream.ok ? (body.access_token ?? body.accessToken) : undefined;
  } catch {
    // A timeout, a redirect, a network failure, or an answer that isn't JSON.
  }
  if (!accessToken) {
    return res.status(502).json({ error: "token exchange failed" });
  }
  res.set("Cache-Control", "no-store").json({ accessToken });
});

app.listen(process.env.PORT ?? 3000);
```

Anyone who can call the route gets a token that can charge, store payment methods and void for your
paypoint, so it has to authenticate the caller and check that they may take payments, the way the rest of
your app does. The sample app's development token server is in
[`Example/PayabliDemo/LocalTokenServer`](Example/PayabliDemo/LocalTokenServer/README.md). It
authenticates no caller, so run it only on your own machine.

### Configure the SDK

Start the session once, before you build either way to pay. It takes your entry point, the environment and
a token provider, and both ways to pay run on it.

```swift
import PayabliSDKCore

let session = try await PayabliSession.initialize(config: PayabliConfig(
    entryPoint: "your-entry-point",
    environment: .sandbox,
    tokenProvider: { try await fetchPayabliAccessToken() }
))
```

| Environment | API host |
|---|---|
| `.sandbox` | `https://api-sandbox.payabli.com` |
| `.production` | `https://api.payabli.com` |

- `PayabliConfig` throws when the entry point is blank.
- Calling `initialize` again with the same entry point, environment and telemetry setting returns the same
  session. A different one throws `invalidConfiguration`, and the session already running stays in place.

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
  use fails with `PayabliErrorType.tokenProviderFailed`.
- Return a token. Don't make SDK calls from inside the provider.

### Device identity

`PayabliSession.deviceId` is this device's identity, the same for every capability and stable for the
install. It is `nil` while the device's secure storage can't be read, such as before the first unlock
after a restart. From Objective-C, read `PayabliSessionObjC.deviceId`, which is also `nil` before the
session is initialized.

## Take a payment

### Card-not-present

`PayabliPayIn` runs on the session `initialize` returned. Show its form, or call it from your own UI:

```swift
import PayabliSDKCore
import PayabliSDKPayIn
import SwiftUI

let payIn = PayabliPayIn(
    session: session,
    operation: .capture,
    requestConfiguration: PayabliPayInRequestConfiguration(
        paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34),
        orderId: order.id // your own reference, to find the payment if its outcome is unknown
    )
)

struct CheckoutView: View {
    let payIn: PayabliPayIn

    var body: some View {
        PayabliPayInView(
            component: payIn,
            onCompleted: { result in order.paymentTransId = result.transaction?.paymentTransId },
            onError: { error in /* see Handle the outcome */ }
        )
    }
}
```

The [card-not-present guide](Sources/PayabliSDKPayIn/README.md) covers the direct API, storing and
charging a saved method, authorizing and capturing, voiding, and the form's configuration and styling.

### Tap to Pay

`PayabliTTP` runs on the session you started. After the one-time setup in the
[Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md), a payment takes three calls:

```swift
import PayabliSDKTapToPay

let ttp = try await PayabliTTP.create()
try await ttp.initialize()
let result = try await ttp.charge(
    type: .sale,
    paymentDetails: PayabliTTPPaymentDetails(amount: 9.99),
    customer: PayabliTTPCustomerData(firstName: "Jane", lastName: "Doe")
)
order.paymentTransId = result.paymentTransId // store it; don't log it
```

The guide covers the entitlements, authorized apps, activating a phone, Apple's terms, and the session
states.

## Handle the outcome

Every charge ends in one of these outcomes, whichever way it was taken. Only **not charged** is safe to
retry.

| Outcome | Card-not-present | Tap to Pay | Retry? |
|---|---|---|---|
| **Charged** | The call returns a result | `charge` returns a `TransactionResult` | No |
| **Not charged** | `PayabliPayInError.transactionFailed`, for example a decline | a `TapToPayError` whose `capture` is `.notCharged`, or a `CancellationError`, which `charge` throws only before the card is read | Yes |
| **Unknown** | `PayabliPayInError.submissionInterrupted` | an error whose `capture` is `.unknown` | Not until you've checked |
| **Charged, not confirmed** | — | an error whose `capture` is `.charged` | No. Reconcile the payment |

When the outcome is unknown, look the transaction up from your backend with
[`GET /api/MoneyIn/details/{transId}`](https://docs.payabli.com/developers/api-reference/moneyin/get-details-for-a-processed-transaction)
before you charge again. `PayabliPayInError.submissionInterrupted` carries no transaction ID, so set
`orderId` on each request and find the transaction by it in the Payabli portal. After
`captureAuthorizedTransaction(_:)`, look up the transaction ID you passed. When a Tap to Pay error
carries no transaction ID, find the transaction in the portal. Store the transaction ID with your order
every time you get one.

Each guide lists its errors in full: [card-not-present](Sources/PayabliSDKPayIn/README.md#outcomes-and-errors)
and [Tap to Pay](Sources/PayabliSDKTapToPay/README.md#outcomes-and-errors).

## Go live

- A **production** entry point, and production OAuth2 credentials with the permissions in
  [Prepare your Payabli account](#prepare-your-payabli-account).
- `.production` as the environment.
- Your token endpoint deployed and authenticating its callers.
- The checklists for what you use: [card-not-present](Sources/PayabliSDKPayIn/README.md#go-live) and
  [Tap to Pay](Sources/PayabliSDKTapToPay/README.md#go-live).

## Reference

### Guides

| Guide | Covers |
|---|---|
| [Card-not-present](Sources/PayabliSDKPayIn/README.md) | The form, the direct API, stored methods, authorize and capture, void, configuration and styling |
| [Tap to Pay](Sources/PayabliSDKTapToPay/README.md) | Entitlements, authorized apps, activation, Apple's terms, states and errors |
| [`Documentation/PayInIntegrationGuide.md`](Documentation/PayInIntegrationGuide.md) and [`PayInOverview.md`](Documentation/PayInOverview.md) | Every card-not-present configuration and styling option |
| [Sample app](Example/PayabliDemo/) | Running both ways to pay against your sandbox paypoint |
| [Payabli developer documentation](https://docs.payabli.com/guides/mobile-components-overview) | The API, OAuth, test accounts and the portal |

### Language support

The SDK is written in Swift, and the card-not-present form is a SwiftUI view.

- **Objective-C.** Start the session with `PayabliSessionObjC`'s
  `initializeWithTokenHandler:entryPoint:environment:telemetryEnabled:completionHandler:`. `PayabliTTP` has
  an `@objc` companion, taking a completion handler, for every `async` method, and is built with
  `createWithCompletionHandler:`. For card-not-present, Objective-C uses `PayabliPayInObjC`, built with
  `createAndReturnError:` on the same session, which offers `addCard` and `addBankAccount`.
- **Objective-C errors.** An SDK error reaches Objective-C as an `NSError` whose `code` is its catalog
  number, with the type's name in `userInfo["PayabliErrorType"]`. Tap to Pay errors are in the
  `com.payabli.ttp` domain, where `userInfo["capture"]` holds the `PayabliTTPCapture` raw value (`0` not
  charged, `1` unknown, `2` charged), `userInfo["paymentTransId"]` is absent when there is no
  transaction ID, and `userInfo["retryAfter"]` holds the wait in seconds when the service asked for one. Card-not-present errors are in the `com.payabli.payIn` domain, and errors from
  `PayabliSessionObjC`'s initializer are in `com.payabli.session`.
- **Flutter, .NET MAUI and React Native.** Wrappers are in [`Bridges/`](Bridges/README.md), which lists the
  status of each.

## Sample app and testing

[`Example/PayabliDemo`](Example/PayabliDemo/) is a SwiftUI app that takes card-not-present and Tap to Pay
payments against your sandbox paypoint, with a bundled token server.

```bash
git clone https://github.com/payabli/sdk-ios.git
cd sdk-ios/Example/PayabliDemo
cp App/Configuration/Secrets.swift.sample App/Configuration/Secrets.swift
```

Fill in `Secrets.swift`, then start the token server as its
[README](Example/PayabliDemo/LocalTokenServer/README.md) describes. In sandbox, use Payabli's
[test cards](https://docs.payabli.com/guides/test-accounts-reference).

## Privacy and data collection

The SDK sends no error or usage reports to Payabli. `PayabliConfig` accepts `telemetryEnabled`, which
changes nothing.

## Versioning and support

> [!IMPORTANT]
> **Notice:** The Payabli iOS SDK is in beta. Until a stable version is released, expect changes to the public
> interface that aren't backward compatible, and read the changes on `main` before you update.

- **No version has been released.** Add the package by branch or by commit as [Installation](#installation)
  describes.
- **`main` changes without notice.** A build that tracks `main` takes whatever is there when the package
  resolves. Use the commit rule for a build that doesn't change.
- **When a stable version is released,** this section gives the version to depend on.

## Support

- Payabli developer documentation: <https://docs.payabli.com/guides/mobile-components-overview>
- Support: support@payabli.com

## License

Commercial. See [LICENSE](LICENSE). The bundled card reader engine is MIT-licensed; attribution is in
[`THIRD_PARTY_LICENSES.txt`](THIRD_PARTY_LICENSES.txt).
