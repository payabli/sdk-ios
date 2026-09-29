# Tap to Pay on iPhone

`PayabliSDKTapToPay` lets your app take a contactless card, phone or watch payment on an iPhone, with no
external reader. This guide is part of the [Payabli iOS SDK](../../README.md); set up the SDK there first.

> [!WARNING]
> **This SDK is in beta.** Its public interface can change in ways that aren't backward compatible. See
> [Versioning and support](../../README.md#versioning-and-support).

## Requirements

### Your app

- iOS 16.7 or later as the deployment target.
- Apple's Tap to Pay entitlement and the App Attest environment entitlement, in
  [Request Apple's entitlement](#request-apples-entitlement).

### The phone

- A physical iPhone XS or newer on iOS 16.7 or later, in a region where Apple supports Tap to Pay on
  iPhone. The simulator can't take a Tap to Pay payment.

### Your account

- A paypoint with Tap to Pay enabled. Ask your Payabli representative.
- OAuth2 credentials with the `tools_init`, `pos_create` and `inboundpayments_create` permissions.

## Before you start

### Request Apple's entitlement

Your app needs `com.apple.developer.proximity-reader.payment.acceptance`. Apple approves it on request,
and approval takes weeks, so request it early. See
[Setting up the entitlement for Tap to Pay on iPhone](https://developer.apple.com/documentation/proximityreader/setting-up-the-entitlement-for-tap-to-pay-on-iphone).

Your app also needs `com.apple.developer.devicecheck.appattest-environment`: `development` for
development builds and `production` for builds you distribute.

### Register your app on the allowlist

The allowlist entry for iOS is your app's **app ID**, your Apple Team ID and bundle ID joined by a dot:
`<TEAM_ID>.<BUNDLE_ID>`, for example `TEAM123456.com.example.checkout`. Register it once per paypoint, from
your backend:

```bash
curl -X POST "https://api-sandbox.payabli.com/api/v2/paypoint/{entryPoint}/apps" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{ "deviceOs": "ios", "appId": "TEAM123456.com.example.checkout", "friendlyName": "Checkout" }'
```

- The call needs the `pos_create` permission. An API token in the `requestToken` header works in place of
  the bearer token.
- `friendlyName` is optional. Calling it again with the same values is safe.
- Register each bundle ID you ship, including debug and white-label builds.

An app that isn't on the allowlist is refused when the device attests. `initialize()` throws a
`PayabliGenericError` whose `code` is `.permissionDenied`, and `sessionState` is `.pendingActivation`, the
same state as a phone that needs a code.

## Set up

```swift
import PayabliSDKCore
import PayabliSDKTapToPay

let ttp = try PayabliTTP(
    tokenProvider: { try await fetchPayabliAccessToken() },
    entryPoint: "your-entry-point",
    appId: "TEAM123456.com.example.checkout",
    environment: .sandbox
)
```

- `PayabliTTP` builds its own session from these values. It is an `ObservableObject`: bind `sessionState`
  and `isReady` in SwiftUI.
- **One paypoint per session.** A `PayabliTTP` serves the entry point it was created with.

## Take a payment

### Initialize

```swift
do {
    try await ttp.initialize()
} catch PayabliTTPError.devicePendingActivation {
    // The phone needs an activation code. See Activate a phone.
} catch PayabliTTPError.termsNotAccepted {
    // The merchant hasn't accepted Apple's terms. See Accept Apple's terms.
}
```

`initialize()` attests the device, fetches its configuration and prepares the reader. The first run on a
phone takes longer than later ones.

### Accept Apple's terms

A merchant accepts Apple's Tap to Pay terms **once per merchant**, not once per phone. Until they do,
`initialize()` stops at `.pendingTerms`, emits `.termsRequired` and throws
`PayabliTTPError.termsNotAccepted`.

Present the terms from a screen where someone with the authority to accept is present, then initialize
again:

```swift
try await ttp.presentTerms()
guard try await ttp.areTermsAccepted() else { return } // declined, or dismissed
try await ttp.initialize()
```

- `presentTerms()` returning doesn't mean the merchant accepted. Ask `areTermsAccepted()`.
- Ask each time instead of caching the answer. Acceptance can change outside your app.
- `areTermsAccepted()` returns `false` when the merchant hasn't accepted, and throws
  `PayabliTTPError.readerSetupFailed` when the reader couldn't answer.

### Activate a phone

A phone takes Tap to Pay payments for a paypoint only after it is activated with a 6-digit code.

- Activation is **per phone and per paypoint**. It isn't per user.
- A reinstall, a restore to a new phone, or a new phone needs a new code.

Until the phone is activated, `initialize()` throws `PayabliTTPError.devicePendingActivation` and
`sessionState` is `.pendingActivation`. An app that isn't on the allowlist lands in the same state, so check
the allowlist before issuing a code.

1. Issue a code for the phone. In the Payabli portal, under **Device Management**, the waiting device's
   options include **Activate device**. The code is valid for 30 minutes, and asking again before it
   expires returns the same code. The API route,
   [Generate Tap to Pay activation code](https://docs.payabli.com/developers/api-reference/device/activation-challenge),
   takes the device's ID, which the SDK doesn't return, so issue codes from the portal.

   The code is six digits and can start with zero, so keep it as a string.
2. Deliver the code to the person holding the phone, and have your app ask for it.
3. Activate, then initialize again:

```swift
try await ttp.activateDevice(activationCode: code)
try await ttp.initialize()
```

### Charge

When `isReady` is `true`, or `sessionState` is `.sessionExpired`, which `charge` refreshes before it reads
the card:

```swift
let result = try await ttp.charge(
    type: .sale,
    paymentDetails: PayabliTTPPaymentDetails(amount: 9.99),
    customer: PayabliTTPCustomerData(firstName: "Jane", lastName: "Doe"),
    invoice: PayabliTTPInvoiceData(invoiceNumber: "INV-9001")
)
order.paymentTransId = result.paymentTransId // store it; don't log it
```

| Parameter | Type | Notes |
|---|---|---|
| `type` | `PayabliTTPPaymentType` | `.sale` is the only type accepted. |
| `paymentDetails` | `PayabliTTPPaymentDetails` | `amount`, the total charged, is required. `serviceFee` defaults to `0`. `serviceFee` is part of `amount`, not added to it: the card is charged `amount`. Leave `currency` out to charge in the paypoint's currency. `paymentDescription` is optional. |
| `customer` | `PayabliTTPCustomerData` | Name the payer with at least one of `firstName`, `lastName`, `customerNumber` or `customerId`. A charge that names nobody can be refused. The other fields (email, phone, billing and shipping address) are optional, and blank values are ignored. |
| `invoice` | `PayabliTTPInvoiceData` | Optional. `invoiceNumber`. |
| `orderDescription` | `String?` | Optional. |

`charge` returns only when the payment is approved. Store `result.paymentTransId` with your order.

## Outcomes and errors

Cancelling the task running `charge` after the transaction has opened doesn't end it silently: it throws
`nfcFailed` or `updateFailed`, carrying `paymentTransId` and `capture`. Follow `capture` as for any other
error.

Every `PayabliTTPError` carries `capture` and `paymentTransId`:

| `capture` | Meaning | What to do |
|---|---|---|
| `.notCharged` | The card wasn't charged. | You can retry. |
| `.unknown` | The outcome isn't known. | Look up `paymentTransId` with [`GET /api/MoneyIn/details/{transId}`](https://docs.payabli.com/developers/api-reference/moneyin/get-details-for-a-processed-transaction) before charging again. When there's no ID, find the transaction in the Payabli portal. |
| `.charged` | The card was charged, but a later step failed. | Don't charge again. Reconcile the payment. |

| Error | When |
|---|---|
| `devicePendingActivation` | The phone needs an activation code. |
| `termsNotAccepted` | The merchant hasn't accepted Apple's terms. |
| `cardDeclined(paymentTransId:)` | The card was declined. |
| `outcomeUnknown(paymentTransId:)` | The processor answered neither an approval nor a decline. |
| `nfcFailed(reason:paymentTransId:)` | The card read failed, for example the card moved away too soon. |
| `updateFailed(reason:paymentTransId:capture:)` | The step after the card read failed. `capture` says whether the card was charged. |
| `initiateFailed(reason:)` | The transaction couldn't be opened. Nothing was charged. |
| `attestationFailed(reason:)`, `attestationRevoked(reason:)` | The device couldn't prove its identity. Check the entitlements. |
| `configFailed(reason:)` | Fetching the device's configuration failed. `reason` says why: a setup gap on the paypoint or device, or a token, network or service failure. |
| `readerSetupFailed(reason:paymentTransId:)` | The reader couldn't be prepared. |
| `readerOSVersionNotSupported(paymentTransId:capture:)` | The iOS version doesn't support Tap to Pay. |
| `invalidState(current:attempted:)`, `notReady(current:)`, `notInitialized` | The call was made in the wrong session state. |
| `tokenExpired`, `networkError(reason:)` | The token or the network failed. Retry later. |
| `activationFailed(reason:)` | The activation code was refused. |

Device attestation and opening a transaction can also throw a core `PayabliError` from `PayabliSDKCore`,
for example `PayabliGenericError` or `PayabliPaymentError`. Catch `any PayabliError` and branch on its
`code`; `.tokenProviderFailed` means your token provider failed.

From Objective-C, these errors arrive as `NSError`. See
[Language support](../../README.md#language-support) in the root README.

## Reference

### Session states

`sessionState` is a `PayabliTTPSessionState`:

| State | Meaning |
|---|---|
| `.idle` | Not started, or activated and waiting for `initialize()`. |
| `.attestingDevice`, `.fetchingConfig`, `.initializingReader(percent:)` | `initialize()` is running. |
| `.ready` | Ready to charge. |
| `.pendingActivation` | The phone needs an activation code, or the app isn't on the paypoint's allowlist. |
| `.pendingTerms` | The merchant hasn't accepted Apple's terms. |
| `.sessionExpired` | The session needs refreshing. The next `charge` refreshes it. |
| `.reinitializing` | The session is being refreshed. |
| `.failed(reason:)` | The session stopped. `reason` says what to do. |

### Failure reasons

| `failureReason` | What to do |
|---|---|
| `.configurationRejected` | The paypoint, the device or its setup is missing something. Retrying won't help; contact Payabli. A token, network or service failure while fetching the configuration lands on `.serviceUnavailable` instead. |
| `.attestationRequired` | The device's attestation was refused or revoked. Check the entitlements, then initialize again. |
| `.serviceUnavailable` | The service or the reader wasn't available. Try again later. |
| `.deviceIneligible` | This iPhone or iOS version can't take Tap to Pay payments. |
| `.sdkInternalError` | Report it to Payabli. |

### Events

`events()` returns an `AsyncStream<PayabliTTPEvent>` for progress UI. Don't log whole events:
`.chargeInitiated` and others carry the transaction ID. Each stream receives the
events emitted after it opens, and nothing emitted before. Open it before you call `initialize()` or
`charge`, and read it in its own task, since the `for await` loop runs until the stream ends:

```swift
let events = ttp.events()          // open the stream first
eventTask = Task {                  // keep the task, and cancel it when your screen goes away
    for await event in events {
        switch event {
        case .chargeInitiated(let paymentTransId): pendingTransId = paymentTransId
        case .readerReady: showReady()
        case .cardDetected: showReading()
        default: break
        }
    }
}
try await ttp.initialize()
```

`.chargeInitiated` carries the transaction ID before the card is read. Keep it, so you can reconcile a
charge whose outcome is unknown. A stream opened after the charge started misses it.

## Go live

- Apple's entitlement on your release build, with `appattest-environment` set to `production`.
- Your release bundle ID on your **production** paypoint's allowlist.
- Apple's terms accepted by the merchant.
- One phone activated and one payment approved end to end, then looked up by its transaction ID.

## Related docs

- [Payabli iOS SDK](../../README.md): setup, the token endpoint, outcomes and go-live
- [Card-not-present payments on iOS](../PayabliSDKPayIn/README.md)
- [Sample app](../../Example/PayabliDemo/)
- [Accept Tap to Pay payments](https://docs.payabli.com/guides/pay-in-developer-tap-to-pay) on docs.payabli.com
- [Generate Tap to Pay activation code](https://docs.payabli.com/developers/api-reference/device/activation-challenge)
