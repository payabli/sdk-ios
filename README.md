# Payabli iOS SDK

The Payabli iOS SDK lets your iPhone app take payments through Payabli. Set it up once, and take a payment
either way on the same session: **card-not-present**, with card or bank account details entered in the SDK's SwiftUI form or
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
| iOS | 16.0 or later. Tap to Pay needs 16.7 or later |
| Toolchain | Xcode 15 or later, Swift 5.9 or later |
| Tap to Pay | A physical iPhone XS or newer. See the [Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md#requirements). Card-not-present runs in the simulator |

## Installation

### Add the SDK

Add the package with Swift Package Manager at the latest version. In Xcode, choose
**File > Add Package Dependencies**, enter the repository URL, and choose the **Up to Next Minor Version**
rule, which starts at the latest version. Until 1.0, a minor version can change the public interface, and
**Up to Next Major Version** would install one the next time the package resolves:

```text
https://github.com/payabli/sdk-ios.git
```

Or declare it in `Package.swift`, with the latest version from the
[Releases](https://github.com/payabli/sdk-ios/releases) page:

```swift
.package(url: "https://github.com/payabli/sdk-ios.git", .upToNextMinor(from: "<latest version>"))
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

Card-not-present needs no app configuration. Tap to Pay needs entitlements, listed in the
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
| Read a transaction back | `inboundpayments_read` |
| Save a payment method | `tokens_create` |
| Initialize Tap to Pay on a phone | `tools_init` and `pos_create` |
| Activate a phone with its code | `pos_create` |
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
- Calling `initialize` again with the same entry point and environment returns the same session, which keeps
  its original token provider. A different one throws `invalidConfiguration`, and the session already running
  stays in place. Once the session's credential is finished (see `tokenExpired` below), `initialize` with any
  configuration starts a fresh session in its place.

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

- The SDK calls the provider before its first request, and again when a token is rejected. Return a newly
  minted token each time, not a cached one.
- Concurrent callers share one call.
- Each call has 30 seconds to return. A call that takes longer, throws, or returns a token the SDK can't
  use fails with `PayabliErrorType.tokenProviderFailed`.
- The SDK doesn't retry a `.tokenProviderFailed` or `.tokenExpired` failure itself. Try again only when someone
  using your app asks to, or wait longer before each attempt.
- Return a token. Don't make SDK calls from inside the provider.

**What `tokenExpired` (1002) means.** It isn't how an expired token reaches you. A token that expires or is
refused once is handled inside the SDK: it asks your provider for a new one, repeats the request, and your call
succeeds. A 1002 means the service refused the token **and** the new one your provider just returned, so even a
freshly minted token is being rejected. Don't treat it as a signal to fetch a token; treat it as a credential your
app has to fix. The usual causes are a token for another environment or entry point, a missing permission, or a
disabled paypoint. Apart from the two cases below, after a 1002 the session's credential is finished: every later
call on that session fails at once with 1002, without sending a request or calling your provider. Fix the cause,
then call `PayabliSession.initialize` again; it starts a fresh session, which calls your provider before its first
request.

Two kinds of 1002 leave the session usable:

- One from Tap to Pay setting up the device (`PayabliTTP.initialize()`, `activateDevice`, or the repair `charge`
  runs first) when the setup's own request was refused, the SDK renewed the token, and the new one was refused
  too. Fix the cause, then call that setup again; it asks your provider for a new token.
- One whose refused token another call had already replaced, or was replacing. Only that call fails; the next
  call uses the new token, and `initialize` with the same configuration returns the same session.

If a setup called again fails at once with 1002 and your provider isn't called, the session's credential is
finished: call `PayabliSession.initialize`, then create the terminal again from the new session.

### Device identity

`PayabliSession.deviceId` is this device's identity, the same for every capability. It is stable across
reinstalls; a device wipe, or moving to another phone even from a backup, gives it a new one. It is `nil` while the device's secure storage can't be read, such as before the first unlock
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

`PayabliTTP` runs on the same session. After the one-time setup in the
[Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md), a payment takes these calls:

```swift
import PayabliSDKTapToPay

let ttp = try await PayabliTTP.create()
try await ttp.initialize()
let result = try await ttp.charge(
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
| **Unknown** | `PayabliPayInError.submissionInterrupted`, or a `CancellationError` when your app cancelled the call | an error whose `capture` is `.unknown` | Not until you've checked |
| **Charged, not confirmed** | — | an error whose `capture` is `.charged` | No. Reconcile the payment |

When the outcome is unknown, look the transaction up before you charge again. On card-not-present, call
`readTransaction(_:)` and check its `status`. From your backend, use
[`GET /api/MoneyIn/details/{transId}`](https://docs.payabli.com/developers/api-reference/moneyin/get-details-for-a-processed-transaction).
`TapToPayError` and `PayabliPayInError.submissionInterrupted` carry the `paymentTransId` to look up when there is
one. When there isn't one, find the transaction in the
Payabli portal before you charge again. On card-not-present, setting `orderId` on each request lets you find it
by your own reference. After `captureAuthorizedTransaction(_:)` or `voidTransaction(_:)`, look up the transaction ID you passed.

Each guide lists its errors in full: [card-not-present](Sources/PayabliSDKPayIn/README.md#outcomes-and-errors)
and [Tap to Pay](Sources/PayabliSDKTapToPay/README.md#outcomes-and-errors).

## Go live

- A **production** entry point, and production OAuth2 credentials with the permissions in
  [Prepare your Payabli account](#prepare-your-payabli-account).
- `.production` in `PayabliConfig`.
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
  `initializeWithTokenHandler:entryPoint:environment:completionHandler:`. `PayabliTTP` has an `@objc`
  companion, taking a completion handler, for every `async` method, and is built with
  `createWithCompletionHandler:`. Its `charge:completion:` takes a `PayabliTTPChargeRequestObjC`, built with
  `initWithPaymentDetails:`, whose `customer`, `invoice`, `orderDescription` and `attempt` are optional and take the
  Swift defaults when unset. For card-not-present, Objective-C uses `PayabliPayInObjC`, built with
  `createAndReturnError:` on the same session. It offers `addCard` and `addBankAccount`, and `capture`,
  `authorize`, `captureAuthorizedTransaction` and `voidTransaction`, which take a `PayabliPayInRequestObjC` or
  `PayabliPayInAuthorizedRequestObjC` and complete with a `PayabliPayInResultObjC`.
- **Objective-C errors.** An SDK error reaches Objective-C as an `NSError` whose `code` is its catalog
  number, with the type's name in `userInfo["PayabliErrorType"]`. `PayabliErrorTypeCode` names every catalog
  number, so compare the code of an error carrying `PayabliErrorType` against a case rather than a number:

  ```objc
  if (error.userInfo[@"PayabliErrorType"] != nil && error.code == PayabliErrorTypeCodeDevicePendingActivation) {
      // Ask for the activation code.
  }
  ```

  Tap to Pay errors are in the
  `com.payabli.ttp` domain, where `userInfo["capture"]` holds the `PayabliTTPCapture` raw value (`0` not
  charged, `1` unknown, `2` charged), `userInfo["paymentTransId"]` is absent when there is no
  transaction ID, and `userInfo["retryAfter"]` holds the wait in seconds when the service asked for one.
  Card-not-present errors are in the `com.payabli.payIn` domain. An error from `capture`, `authorize`,
  `captureAuthorizedTransaction` or `voidTransaction` carries `userInfo["capture"]`: `1` when the payment may have been
  taken, including a refusal with code 1023 because another call for the payment is open, and `0` when it wasn't.
  When it's `1`, `userInfo["paymentTransId"]` holds the transaction ID and
  `userInfo["paymentReference"]` the payment's reference; each is absent when there is none. Errors from `PayabliSessionObjC`'s initializer are in `com.payabli.session`.

### Other technologies

> [!NOTE]
> **Guidance only:** This section suggests one way to take Payabli payments from a React Native or Flutter app.
> It's guidance, not a supported implementation. Payabli doesn't state that any example here is a complete or
> direct implementation, or that it fits your app as written. The examples are subject to limitations, including
> the frameworks' own versions and requirements, and Payabli doesn't build or test them. Your team designs,
> builds, tests and maintains its integration, and is responsible for it.

There is no React Native or Flutter package. Your app adds a small native module that exposes a few calls to
JavaScript or Dart, and runs this SDK underneath on iOS and the Payabli Android SDK on Android. The same applies to any
other technology, such as .NET MAUI: it binds the Objective-C surface in [Language support](#language-support).

A module keeps these rules:

- **Card data never crosses into JavaScript or Dart.** The module presents the SDK's own form and the Tap to Pay
  sheet, and returns only the outcome.
- **The token is fetched natively.** The module's `tokenProvider` calls your token endpoint from Swift. If it
  routes through JavaScript or Dart instead, give each request its own pending promise or future and fail it after
  30 seconds: one shared slot can leave a request waiting forever.
- **Every call resolves or rejects exactly once**, including when the customer closes the form.

Give the module the same calls on both platforms, so your JavaScript or Dart has one code path:

| Call | What it does | Result |
|---|---|---|
| `initialize(entryPoint, environment)` | Starts the app's one Payabli session | nothing, or an error with a `code` |
| `payWithCard({ amount, orderId })` | Presents the card-not-present form | a `PaymentOutcome` |
| `tapToPay({ amount, orderId })` | Takes a Tap to Pay payment | a `PaymentOutcome` |
| `presentTerms()` | Shows Apple's Tap to Pay terms to the merchant | whether they accepted |
| `activateDevice(code)` | Activates this phone with its 6-digit code | nothing, or an error with a `code` |
| `sessionState` (a stream) | Tap to Pay readiness, one value per change | `idle`, `attestingDevice`, `fetchingConfig`, `initializingReader`, `ready`, `sessionExpired`, `reinitializing`, `pendingActivation`, `pendingTerms`, `charging` or `failed` |

A `PaymentOutcome` maps [Handle the outcome](#handle-the-outcome) to three answers: `charged` (store
`paymentTransId`, don't charge again), `notCharged` (the customer can try again) and `unknown` (look the payment
up by `paymentTransId` before charging again; without one, find it by your `orderId` on card-not-present, or in
the Payabli portal for Tap to Pay). `tapToPay` answers a fourth, `unsupported`,
where Tap to Pay isn't available. A failure that isn't a payment outcome, such as a session that didn't start,
rejects the call in React Native and throws a `PlatformException` in Flutter, with a `code`.

**React Native.** Create the module with the [Expo Modules API](https://docs.expo.dev/modules/overview/)
(`npx create-expo-module@latest --local`), and declare it in TypeScript:

```ts
import { NativeModule, requireNativeModule } from 'expo';

export type PaymentRequest = { amount: number; orderId: string };
export type PaymentOutcome =
  | { status: 'charged' | 'notCharged' | 'unknown'; paymentTransId: string | null }
  | { status: 'unsupported' };

declare class PayabliModule extends NativeModule<{
  onSessionState(event: { state: string }): void;
}> {
  initialize(entryPoint: string, environment: 'sandbox' | 'production'): Promise<void>;
  payWithCard(request: PaymentRequest): Promise<PaymentOutcome>;
  tapToPay(request: PaymentRequest): Promise<PaymentOutcome>;
  presentTerms(): Promise<boolean>;
  activateDevice(code: string): Promise<void>;
}

export const Payabli = requireNativeModule<PayabliModule>('Payabli');

// const outcome = await Payabli.payWithCard({ amount: 12.34, orderId: 'A-1001' });
```

The Swift half is an `AsyncFunction` per call, run on the main queue so the SDK's screens can be presented.
Expo Go can't load your own native code, so run a development build (`npx expo run:ios`). React Native's
[Turbo Native Modules](https://reactnative.dev/docs/turbo-native-modules-introduction) work too: declare the same
calls as a spec, and have the module's Objective-C++ class call a Swift file that makes the SDK calls. The
card-not-present form is a SwiftUI view, which Objective-C can't present.

**Flutter.** Describe the calls once with [Pigeon](https://pub.dev/packages/pigeon), which generates the Dart API
and the Swift and Kotlin interfaces your native code implements:

```dart
import 'package:pigeon/pigeon.dart';

enum PaymentStatus { charged, notCharged, unknown, unsupported }

class PaymentRequest {
  PaymentRequest({required this.amount, required this.orderId});
  double amount;
  String orderId;
}

class PaymentResult {
  PaymentResult({required this.status});
  PaymentStatus status;
  String? paymentTransId;
}

@HostApi()
abstract class PayabliHostApi {
  @async
  void initialize(String entryPoint, bool sandbox);
  @async
  PaymentResult payWithCard(PaymentRequest request);
  @async
  PaymentResult tapToPay(PaymentRequest request);
  @async
  bool presentTerms();
  @async
  void activateDevice(String code);
}
```

Generate the code, naming where each file goes in your app:

```sh
dart run pigeon --input pigeons/payabli_api.dart \
  --dart_out lib/payabli_api.g.dart \
  --swift_out ios/Runner/PayabliApi.g.swift \
  --kotlin_out android/app/src/main/kotlin/com/example/app/PayabliApi.g.kt \
  --kotlin_package com.example.app
```

Then implement `PayabliHostApi` in Swift and set it up on the engine's binary messenger at startup. Without Pigeon, a `MethodChannel` and an `EventChannel`
([platform channels](https://docs.flutter.dev/platform-integration/platform-channels)) carry the same calls.

Each call is one SDK call underneath:

| Call | iOS | Android |
|---|---|---|
| `initialize` | `PayabliSession.initialize(config:)` | `PayabliSession.initialize(config, HostBindings(context))` |
| `payWithCard` | present `PayabliPayInView` for a `PayabliPayIn` with `operation: .capture` | show `PayabliPayInForm` in an activity |
| `tapToPay` | `PayabliTTP.create()`, `initialize()`, then `charge(paymentDetails:)` | answer `unsupported` |
| `presentTerms` | `presentTerms()`, then `areTermsAccepted()` | answer `false` |
| `activateDevice` | `activateDevice(activationCode:)`, then `initialize()` | reject with `UNSUPPORTED` |
| `sessionState` | `PayabliTTP`'s `$sessionState` | send `idle` once |

Tap to Pay needs a physical iPhone, and the setup in the [Tap to Pay guide](Sources/PayabliSDKTapToPay/README.md).

## Sample app and testing

[`Example/PayabliDemo`](Example/PayabliDemo/) is a SwiftUI app that takes card-not-present and Tap to Pay
payments against your sandbox paypoint, with a bundled token server.

```bash
git clone https://github.com/payabli/sdk-ios.git
cd sdk-ios/Example/PayabliDemo
cp App/Configuration/Secrets.swift.sample App/Configuration/Secrets.swift
cp SDK/ExtraEnvironments.swift.sample SDK/ExtraEnvironments.swift
```

Fill in `Secrets.swift`, then start the token server as its
[README](Example/PayabliDemo/LocalTokenServer/README.md) describes. In sandbox, use Payabli's
[test cards](https://docs.payabli.com/guides/test-accounts-reference).

## Privacy and data collection

The SDK sends error and usage events to Payabli, with no card, payer or account data. The events are
not listed.

Core, PayIn and Tap to Pay each ship a privacy manifest declaring what they collect, so Xcode's privacy report
for your app includes it:

- `PayabliSDKCore`, which every product includes, collects the device ID, performance data, other diagnostic
  data and product interaction, linked to the user, not used for tracking, for app functionality and analytics.
- `PayabliSDKPayIn` collects the payment info, name, email address and customer number the payer enters in
  its form, linked to the user, not used for tracking, for app functionality.
- `PayabliSDKTapToPay` declares nothing beyond Core, because Apple's reader takes the card.

The manifests don't cover data your app passes to the SDK, such as the customer record, invoice or order
description on a payment. The SDK sends that data to Payabli with the payment, and your app declares it.

Every request the SDK sends to Payabli carries an `X-Pyb-Client` header with the SDK version, the platform, the OS
version, the device model, the locale and the device ID described under [Device identity](#device-identity).
A value that's missing, blank or isn't printable ASCII is left out. The header can't be turned off.

## Versioning and support

> [!IMPORTANT]
> **Notice:** The Payabli iOS SDK is in beta. Until a stable version is released, expect changes to the public
> interface that aren't backward compatible, and read the release notes before you update.

- **Depend on the latest version** as [Installation](#installation) describes. Each version and its
  notes are on the [Releases](https://github.com/payabli/sdk-ios/releases) page.
- **`main` holds the latest release.** Work toward the next release isn't published for integration; depend on a
  released version.
- **When a stable version is released,** this section says so.

## Support

- Payabli developer documentation: <https://docs.payabli.com/guides/mobile-components-overview>
- Support: support@payabli.com

## License

Commercial. See [LICENSE](LICENSE). Third-party components and their licenses are listed in
[`THIRD_PARTY_LICENSES.txt`](THIRD_PARTY_LICENSES.txt).
