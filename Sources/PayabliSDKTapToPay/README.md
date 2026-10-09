# Tap to Pay on iPhone

`PayabliSDKTapToPay` lets your app take a contactless card, phone or watch payment on an iPhone, with no
external reader. This guide is part of the [Payabli iOS SDK](../../README.md); set up the SDK and its session there first.

> [!IMPORTANT]
> **Notice:** This SDK is in beta. Its public interface can change in ways that aren't backward compatible. See
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
- OAuth2 credentials with these permissions:

  | Operation | Permission |
  |---|---|
  | `initialize()` | `tools_init` and `pos_create` |
  | `activateDevice(activationCode:)` | `tools_init` and `pos_create` |
  | `charge` | `inboundpayments_create` |
  | Registering an authorized app through the API | `pos_create` |

## Before you start

### Request Apple's entitlement

Your app needs `com.apple.developer.proximity-reader.payment.acceptance`. Apple approves it on request,
and approval takes weeks, so request it early. See
[Setting up the entitlement for Tap to Pay on iPhone](https://developer.apple.com/documentation/proximityreader/setting-up-the-entitlement-for-tap-to-pay-on-iphone).

Your app also needs `com.apple.developer.devicecheck.appattest-environment`: `development` for
development builds and `production` for builds you distribute.

### Register your app as an authorized app

The authorized app entry for iOS is your app's **app ID**, its App ID prefix and bundle ID joined by a dot:
`<APP_ID_PREFIX>.<BUNDLE_ID>`, for example `TEAM123456.com.example.checkout`. The App ID prefix is your
Team ID for most apps; an older App ID can have a different one, shown in the Apple Developer portal. Register it once per paypoint,
in the Payabli portal under **Pay In > Devices > Device management**, **⋯ > Authorized apps**, or from your
backend:

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
- The SDK reads the app ID from the signed app and sends it when the device attests, so your code never
  passes it.

An app that isn't an authorized app is refused when the device attests, with an HTTP 403. `initialize()`
throws a `TapToPayError` whose `type` is `.permissionDenied`, and `sessionState` is
`.failed(reason: .configurationRejected)`. Register the app, then initialize again.

## Set up

```swift
import PayabliSDKCore
import PayabliSDKTapToPay

let session = try await PayabliSession.initialize(config: PayabliConfig(
    entryPoint: "your-entry-point",
    environment: .sandbox,
    tokenProvider: { try await fetchPayabliAccessToken() }
))
let ttp = try await PayabliTTP.create()
```

- Start the session once, before `create()`. `create()` throws when no session has been started.
- Card-not-present payments run on the same session: pass `session` to `PayabliPayIn`.
- `PayabliTTP` is an `ObservableObject`: bind `sessionState` and `isReady` in SwiftUI.

## Take a payment

### Initialize

```swift
do {
    try await ttp.initialize()
} catch let error as TapToPayError where error.type == .devicePendingActivation {
    // The phone needs an activation code. See Activate a phone.
} catch let error as TapToPayError where error.type == .termsNotAccepted {
    // The merchant hasn't accepted Apple's terms. See Accept Apple's terms.
}
```

`initialize()` attests the device, fetches its configuration and prepares the reader. It is safe to call
again while no charge is running. The first run on a phone takes longer than later ones.

### Accept Apple's terms

A merchant accepts Apple's Tap to Pay terms **once per merchant**, not once per phone. Until they do,
`initialize()` stops at `.pendingTerms` and throws a `TapToPayError` whose `type` is `.termsNotAccepted`.

Present the terms from a screen where someone with the authority to accept is present, then initialize
again:

```swift
try await ttp.presentTerms()
guard try await ttp.areTermsAccepted() else { return } // declined, or dismissed
try await ttp.initialize()
```

- `presentTerms()` shows Apple's Tap to Pay on iPhone Terms and Conditions sheet, where the merchant
  accepts for their merchant identifier. Once accepted on one iPhone, other iPhones for the same merchant
  don't ask again. Apple's
  [Tap to Pay on iPhone guidelines](https://developer.apple.com/design/human-interface-guidelines/tap-to-pay-on-iphone)
  say when to show it and to whom.
- `presentTerms()` returning doesn't mean the merchant accepted. Ask `areTermsAccepted()`.
- Ask each time instead of caching the answer. Acceptance can change outside your app.
- `areTermsAccepted()` returns `false` when the merchant hasn't accepted, and throws a `TapToPayError`
  when the reader couldn't answer.

### Activate a phone

A phone takes Tap to Pay payments for a paypoint only after it is activated with a 6-digit code.

- Activation is **per phone and per paypoint**. It isn't per user.
- A reinstall, a restore to a new phone, or a new phone needs a new code.
- One install can hold activations for up to four paypoints. Activating a fifth drops the one used least
  recently, which then needs to be set up again the next time it's used.

Until the phone is activated, `initialize()` throws a `TapToPayError` whose `type` is
`.devicePendingActivation`, and
`sessionState` is `.pendingActivation(activationId:)`. An app that isn't an authorized app, or credentials
without `tools_init` or `pos_create`, land on `.failed(reason: .configurationRejected)` on a phone with
no setup stored for the paypoint from an earlier run. Credentials without
`inboundpayments_create` reach `.ready`, and `charge` then throws a `TapToPayError` whose `type` is
`.permissionDenied`, before the card is read.

The code is six digits and can start with zero, so keep it as a string. It's valid for 30 minutes, and
asking for one again before it expires returns the same code. There are two ways to get it to the app, and
both end the same way: activate, then initialize again.

```swift
try await ttp.activateDevice(activationCode: code)
try await ttp.initialize()
```

#### Option 1: Manual

Someone issues the code and gives it to the person holding the phone, and your app asks for it.

- **From the portal:** under **Pay In > Devices > Device management**, choose
  **⋯ > Generate activation code**.
- **From a backend tool:** call
  [Generate Tap to Pay activation code](https://docs.payabli.com/developers/api-reference/device/activation-challenge)
  with the paypoint's entry point and this phone's activation ID in the request's `deviceId` field. The app
  reads the ID from the pending state, as in option 2, step 1, and shows it to whoever runs the tool.

#### Option 2: Automated, in the app

No person handles the code.

1. Read the phone's activation ID. It's on the pending state, and only there:

   ```swift
   if case let .pendingActivation(activationId) = ttp.sessionState {
       // Send activationId to your backend.
   }
   ```

   From Objective-C, read `ttp.activationId`, which is `nil` unless an activation is owed. An app that
   lost the ID initializes again and lands on the same one.
2. Send the activation ID to your backend. Your backend calls
   [Generate Tap to Pay activation code](https://docs.payabli.com/developers/api-reference/device/activation-challenge)
   with the paypoint's entry point and the activation ID in the request's `deviceId` field, and returns the
   code.

   Anyone who can call this route can set up a phone to take payments for your paypoint, so it has to
   authenticate the caller and check that they may take payments, the way your token endpoint does.
3. Activate, then initialize again.

The activation ID is read from this phone's own state, never looked up as the latest pending device on the
paypoint, so another phone enrolling on the same paypoint can't change it.

### Charge

When `sessionState` is `.ready`, or `.sessionExpired`, which `charge` refreshes before it reads the card:

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

Every failure is a `TapToPayError`, apart from a cancellation, which can end the call as
`CancellationError`. Cancelling the task running `charge` after the transaction has opened doesn't end it
silently: it throws a `TapToPayError` carrying `paymentTransId` and `capture`. Follow `capture` as for any
other error.

A `TapToPayError` carries the catalog entry for its cause:

- `category` says what to do, such as `.credential` (call `initialize()` again) or `.outcomeUnknown`
  (find the transaction before repeating the call). Choose your remedy from `category`.
- `type` names the cause, for a case your app handles on its own, such as `.devicePendingActivation`.
- `code` is the catalog number Payabli support reads. Give it to them with the failure.
- `message` is fixed text, safe to show and to log. `reason` is a short summary and `detail` a longer
  explanation, from the service, the reader or the SDK, when there is one. Show them, but don't log them: the
  service's text can repeat what the request carried.
- `retryAfter` is the wait the service asked for before trying again, when it asked for one and the
  failure carries it.

These Tap to Pay causes are ones your app handles, with their codes:

| `type` | `code` | `category` | `message` |
|---|---|---|---|
| `.activationCodeMalformed` | 3023 | `.invalidRequest` | The activation code must be six digits. |
| `.activationCodeIncorrect` | 3024 | `.invalidRequest` | The activation code is incorrect. |
| `.activationCodeExpired` | 3025 | `.configuration` | The activation code has expired. |
| `.activationAttemptsExhausted` | 3026 | `.configuration` | Too many incorrect activation codes were entered. |
| `.activationCodeNotIssued` | 3027 | `.configuration` | No activation code has been issued for this device. |
| `.deviceNotPending` | 3028 | `.invalidRequest` | This device is not waiting for activation. |
| `.terminalNotReady` | 3029 | `.invalidRequest` | The terminal is not ready for this call. |

It also carries `capture` and `paymentTransId`:

| `capture` | Meaning | What to do |
|---|---|---|
| `.notCharged` | The card wasn't charged. | You can retry. |
| `.unknown` | The outcome isn't known. | Look up `paymentTransId` with [`GET /api/MoneyIn/details/{transId}`](https://docs.payabli.com/developers/api-reference/moneyin/get-details-for-a-processed-transaction) before charging again. When there's no ID, find the transaction in the Payabli portal. |
| `.charged` | The card was charged, but a later step failed. | Don't charge again. Reconcile the payment. |

`PayabliTTP.create()` throws a `TapToPayError` whose `type` is `.sessionNotInitialized` (1019) when no session
has been started: call `PayabliSession.initialize` first.

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
| `.charging(activity:)` | `charge` is running, and `isReady` is `false` until it ends, unless `initialize()` is called during it and rebuilds the session. It ends at `.ready`, at `.sessionExpired` when the reader session was spent, or at `.failed(reason: .deviceSetupRequired)` when the device's registration is gone. `activity` is `.opening`, `.waitingForCard` or `.closing`, or a prompt the reader raised during the tap: `.cardDetected`, `.cardRemovalRequested`, `.cardReadRetryRequested`, `.pinEntryRequested`, `.pinEntryCompleted` or `.readerPromptDismissed`. The outcome is what `charge` returns or throws. |
| `.pendingActivation(activationId:)` | The phone needs an activation code. `activationId` is what the activation route's `deviceId` field takes. |
| `.pendingTerms` | The merchant hasn't accepted Apple's terms. |
| `.sessionExpired` | The session needs refreshing. The next `charge` refreshes it. |
| `.reinitializing` | The session is being refreshed. |
| `.failed(reason:)` | The session stopped. `reason` says what to do. |

### Failure reasons

| `failureReason` | What to do |
|---|---|
| `.configurationRejected` | The paypoint, the app, the device or its setup is missing something, such as the app's Keychain entitlement. Retrying won't help; contact Payabli. A token, network or service failure while fetching the configuration lands on `.serviceUnavailable` instead. |
| `.deviceSetupRequired` | This device must be set up again: its setup was refused or revoked, its registration was replaced, or its key is gone. Check the entitlements, then initialize again. |
| `.serviceUnavailable` | The service, Apple's attestation service or the reader wasn't available. Try again later. |
| `.deviceIneligible` | This iPhone or iOS version can't take Tap to Pay payments, the card reader refused it, or the app has no bundle identifier. If an iPhone that meets the requirements lands here, contact Payabli before replacing it. |
| `.sdkInternalError` | Report it to Payabli. |
| `.deviceKeyUnavailable` | This device's secure storage is unavailable, for example before the first unlock after a restart. Initialize again. If it keeps failing, the phone is the cause. |

### Watching the session

`PayabliTTP` is an `ObservableObject`, so a SwiftUI view reads `sessionState` and redraws when it changes:

```swift
struct TerminalView: View {
    @ObservedObject var ttp: PayabliTTP

    var body: some View {
        switch ttp.sessionState {
        case .ready: Button("Charge") { Task { await charge() } }
        case .charging(.waitingForCard): Text("Hold a card near the top of the iPhone")
        case .charging(.cardRemovalRequested): Text("Remove the card")
        case .initializingReader(let percent): ProgressView(value: Double(percent ?? 0), total: 100)
        default: ProgressView()
        }
    }
}
```

How a call ended is what it returns or throws. A failure raised after the payment was opened carries its
`paymentTransId`.

From Objective-C, `addSessionStateObserver(_:)` calls a block on the main thread after every change. The
block carries nothing: read `sessionStateCode` and the accessors beside it, such as `chargeActivity`, then call `cancel()` on the
returned observation when your screen goes away.

## Go live

- Apple's entitlement on your release build, with `appattest-environment` set to `production`.
- Your release bundle ID among your **production** paypoint's authorized apps.
- Apple's terms accepted by the merchant.
- One phone activated and one payment approved end to end, then looked up by its transaction ID.

## Related docs

- [Payabli iOS SDK](../../README.md): setup, the token endpoint, outcomes and go-live
- [Card-not-present payments on iOS](../PayabliSDKPayIn/README.md)
- [Sample app](../../Example/PayabliDemo/)
- [Accept Tap to Pay payments](https://docs.payabli.com/guides/pay-in-developer-tap-to-pay) on docs.payabli.com
- [Generate Tap to Pay activation code](https://docs.payabli.com/developers/api-reference/device/activation-challenge)
