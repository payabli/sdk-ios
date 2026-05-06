# Payabli iOS SDK

## Summary

The Payabli iOS SDK enables iPhone applications to accept in-person
card payments using Apple's Tap to Pay on iPhone. No external card
reader is required: any iPhone XS or newer running iOS 16.7 or later is
supported. The SDK handles device attestation, session management, NFC
card reading, retry logic, and reconciliation with the Payabli backend;
the host application provides the checkout user interface.

```swift
import PayabliSDKTapToPay

let ttp = PayabliTTP(
    accessToken: token,
    tokenProvider: { try await yourBackend.fetchPayabliAccessToken() },
    entryPoint: "your-entrypoint",
    appId: "TEAM123456.com.yourcompany.app",
    environment: .sandbox
)

try await ttp.initialize()
let result = try await ttp.charge(
    type: .sale,
    paymentDetails: PayabliTTPPaymentDetails(amount: 9.99)
)
print("Transaction captured. ID:", result.paymentTransId)
```

`PayabliTTP` conforms to `ObservableObject`. The `sessionState` and
`isReady` properties may be bound directly in SwiftUI, and the
`events()` AsyncSequence emits fine-grained progress updates.

### Capabilities

| Capability                    | Notes                                                                    |
| ----------------------------- | ------------------------------------------------------------------------ |
| Tap to Pay on iPhone          | Card-present NFC; no external reader required.                           |
| Swift and Objective-C APIs    | First-class `@objc` surface for MAUI, Flutter, and React Native hosts.   |
| Built-in App Attest           | Cold and warm device attestation, cached automatically.                  |
| Pending-device activation     | Out-of-band OTP flow for first-time devices.                             |
| Optional telemetry            | Pluggable Sentry and PostHog transports; bring your own instance.        |

### System requirements

You need the following to build and run the SDK:
- iPhone XS or newer
- iOS 16.7 or later
- Xcode 15 or later
- Swift 5.9 or later (Swift Package Manager 5.9+, bundled with Xcode 15)

### Modules

The SDK ships as several focused frameworks. Most applications only
need `PayabliSDKTapToPay`.

| Module                  | When to select it                                                            |
| ----------------------- | ---------------------------------------------------------------------------- |
| `PayabliSDK`            | Umbrella product linking Core and TapToPay together.                         |
| `PayabliSDKCore`        | Core building blocks (config, auth, transport).                              |
| `PayabliSDKTapToPay`    | Tap to Pay on iPhone. The product most applications require.                 |
| `PayabliCardReaderCore` | Tap to Phone engine. Pulled in transitively; no explicit link required.      |
| `PayabliSDKTelemetry`   | Optional Sentry and PostHog plumbing; bring your own instance.               |
| `PayabliSDKTestUtils`   | Test fixtures (`StubURLProtocol`, `InMemorySecureStorage`, mocks). Link in test targets only. |

---

## Prerequisites

You need the following to integrate the SDK and process transactions:

### Device and operating system

- iPhone XS or newer
- iOS 16.7 or later
- A region where Tap to Pay on iPhone is supported by Apple
- The device unlocked at the time of the transaction

The SDK validates device eligibility during the `initialize()` method.

### Apple entitlements

The application's provisioning profile requires two entitlements:

1. **`com.apple.developer.proximity-reader.payment.acceptance`.** 
   This entitlement is allowlisted by Apple and must be requested
   explicitly. See [Setting Up the Entitlement](https://developer.apple.com/documentation/proximityreader/setting-up-the-entitlement-for-tap-to-pay-on-iphone) 
   on Apple's docs for more information.

2. **`com.apple.developer.devicecheck.appattest-environment`.** 
   Set to `production` for release builds, or `development` for development
   builds. The value must match the `environment` passed to `PayabliTTP`.

### Payabli entrypoint

You need a Tap to Pay-enabled entrypoint provisioned by Payabli.
The entrypoint slug (example: `acmePay`) is supplied to the SDK
as the `entryPoint` constructor parameter and is also the path
component of the merchant dashboard URL
(`https://app.payabli.com/<entryPoint>/signin`).

### Authorized application on the paypoint allowlist

To do attestation successfully, you must authorize the application's `appId` (`<TEAM_ID>.<BUNDLE_ID>`)
on the entrypoint allowlist. Two methods are supported:

- **Dashboard.** Sign in to the entrypoint at
  `https://app.payabli.com/<entryPoint>/signin` (sandbox:
  `https://app-sandbox.payabli.com/<entryPoint>/signin`), navigate to
  **Settings → Devices → Authorized Apps**, and add the `appId`.
- **API.** Issue `POST /api/v2/paypoint/<entryPoint>/apps` against the
  same host configured for the SDK (`https://api.payabli.com` for
  production, `https://api-sandbox.payabli.com` for sandbox):

  ```json
  {
    "deviceOs": "ios",
    "appId": "<TEAM_ID>.<BUNDLE_ID>",
    "friendlyName": "My iOS App"
  }
  ```

  `deviceOs` must be `"ios"`. `friendlyName` is optional. The endpoint
  is idempotent on `(entryPoint, deviceOs, appId)` and is safe to
  invoke from a provisioning script.

If the application's `appId` isn't registered, the `initialize()` method rejects
attestation with `PayabliTTPError.attestationFailed`.

### Backend token endpoint

The SDK consumes short-lived `access_token` values. The `clientSecret` issued
to the merchant must never reside on the device; it is held by the host
application's backend, which exchanges it for an `access_token` via
Payabli's `POST /api/v2/token/serverside` endpoint and returns the
token to the iOS application.

```text
  iOS App            Host Backend            Payabli API
     │                    │                       │
     │  request token     │                       │
     ├───────────────────▶│                       │
     │                    │  POST /v2/token/serverside
     │                    │  { clientId, clientSecret }
     │                    ├──────────────────────▶│
     │                    │                       │
     │                    │           access_token│
     │                    │◀──────────────────────┤
     │      access_token  │                       │
     │◀───────────────────┤                       │
     ▼                    ▼                       ▼
```

You need a backend endpoint that performs this exchange.
See [Implementing the token provider](#implementing-the-token-provider) for implementation details.

---

## Installation

### Swift Package Manager

In Xcode, choose **File → Add Packages…** and enter the repository
URL:

```
https://github.com/payabli/payabli-sdk-ios.git
```

Alternatively, declare the dependency in `Package.swift`:

```swift
.package(url: "https://github.com/payabli/payabli-sdk-ios.git", branch: "main")
```

Link the required product. Most applications only need
`PayabliSDKTapToPay`:

```swift
.product(name: "PayabliSDKTapToPay", package: "payabli-sdk-ios")
```

`PayabliSDKTapToPay` transitively links `PayabliSDKCore` and
`PayabliCardReaderCore`; no additional product references are required.

For host-app integration tests, also link `PayabliSDKTestUtils`:

```swift
.testTarget(
    name: "MyAppTests",
    dependencies: [
        "MyApp",
        .product(name: "PayabliSDKTestUtils", package: "payabli-sdk-ios")
    ]
)
```

It ships `StubURLProtocol`, `InMemorySecureStorage`, `MockTapToPayProvider`,
`MockAppAttestor`, `MockDeviceAttestationService`, and
`InMemoryTelemetryTransport` so test bundles don't need to re-implement
these. Don't link it from production targets.

---

## Usage

### Configuring `PayabliTTP`

`PayabliTTP` is constructed with four parameters:

```swift
let ttp = PayabliTTP(
    accessToken: try await yourBackend.fetchPayabliAccessToken(),
    tokenProvider: { try await yourBackend.fetchPayabliAccessToken() },
    entryPoint: "your-entrypoint",
    appId: "TEAM123456.com.yourcompany.app",
    environment: .sandbox
)
```

| Parameter        | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `accessToken`    | A valid short-lived bearer token issued by the host backend.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `tokenProvider`  | An `async throws -> String` closure. The SDK invokes it to obtain a fresh token after a `401 Unauthorized` response. Concurrent refresh attempts are deduplicated.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `entryPoint`     | The entrypoint slug provisioned by Payabli (see [Payabli entrypoint](#payabli-entrypoint)).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `appId`          | The application's identity in the form `<TEAM_ID>.<BUNDLE_ID>`. The `TEAM_ID` is the 10-character team identifier from the [Apple Developer account](https://developer.apple.com/account); the `BUNDLE_ID` is the application's bundle identifier (e.g., `TEAM123456.com.acme.checkout`). The same `appId` must be authorized on the paypoint allowlist (see [Authorized application on the paypoint allowlist](#authorized-application-on-the-paypoint-allowlist)). App Attest uses `appId` to verify that the binary on the device matches the registered application; a mismatch surfaces as `PayabliTTPError.attestationFailed`. |
| `environment`    | Selects the target Payabli API (see the values table below). The value must match the `appattest-environment` entitlement: `development` for `.sandbox`, `production` for `.production`.                                                                                                                                                                                                                                                                                                                                                                                                                                                            |

Environment values:

| Value         | Base URL                          |
| ------------- | --------------------------------- |
| `.sandbox`    | `https://api-sandbox.payabli.com` |
| `.production` | `https://api.payabli.com`         |

### Implementing the token provider

The `tokenProvider` closure returns a fresh `access_token` from the
host backend. You need two things: a backend endpoint that performs the exchange with Payabli, and an iOS closure that calls it.

#### Backend endpoint

You can use any HTTP server that can forward the `clientId` / `clientSecret`
exchange. This Node.js example shows how to implement the endpoint using Express:

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
  console.log("Token server ready"));
```

For production deployments, store `clientId` and `clientSecret` in
environment variables, and protect the endpoint with the same
authentication scheme used in the host application (session
cookie, partner JWT, mTLS, or equivalent).

#### iOS closure

A standard implementation of the closure passed to `PayabliTTP` sends
a `POST` request to the backend endpoint and returns the token:

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

When the SDK receives a `401 Unauthorized`, it invokes `tokenProvider`,
retries the request with the new token, and deduplicates concurrent
refreshes. The host application isn't required to track expirations,
schedule refreshes, or implement debouncing.

### Initialization and charging

`initialize()` performs device attestation and brings the session to
the `.ready` state. It is intended to be called once per session;
subsequent launches reuse cached attestation and complete substantially
faster than the first launch.

```swift
try await ttp.initialize()

let result = try await ttp.charge(
    type: .sale,
    paymentDetails: PayabliTTPPaymentDetails(amount: 9.99),
    customer: PayabliTTPCustomerData(firstName: "Jane", lastName: "Doe"),
    invoice: PayabliTTPInvoiceData(invoiceNumber: "INV-9001")
)

print("Transaction captured. ID:", result.paymentTransId)
```

The `charge(...)` method does three things: 
1. call `POST /MoneyIn/initiate`
2. NFC card read
3. call `PATCH /MoneyIn/update/{id}`

If the final update fails after retries, the transaction is still authorized on the processor
side and must be reconciled out of band. This case is rare.

### `charge(...)` reference

```swift
public func charge(
    type: PayabliTTPPaymentType,
    paymentDetails: PayabliTTPPaymentDetails,
    customer: PayabliTTPCustomerData = .init(),
    invoice: PayabliTTPInvoiceData = .init(),
    orderDescription: String? = nil
) async throws -> TransactionResult
```

| Parameter         | Type                          | Required | Notes                                                                                                                                                                                                                  |
| ----------------- | ----------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `type`            | `PayabliTTPPaymentType`       | yes      | v1.0 supports `.sale` only.                                                                                                                                                                                            |
| `paymentDetails`  | `PayabliTTPPaymentDetails`    | yes      | Bundles `amount` (required), `serviceFee` (default `0`), optional `currency` (omitted when `nil`; the backend then authorizes in the merchant's configured processor currency), and optional `paymentDescription`.    |
| `customer`        | `PayabliTTPCustomerData`      | no       | Cardholder snapshot (name, customer ID, billing and shipping addresses). Persisted at `/initiate`. Defaults to anonymous.                                                                                              |
| `invoice`         | `PayabliTTPInvoiceData`       | no       | Invoice metadata (`invoiceNumber`). Persisted at `/initiate`.                                                                                                                                                          |
| `orderDescription`| `String?`                     | no       | Free-form description forwarded to the backend at the top-level `orderDescription` key.                                                                                                                                |

`PayabliTTPCustomerData` (every field optional; blank values are
ignored):

| Field                 | Type      | Purpose                                                                |
| --------------------- | --------- | ---------------------------------------------------------------------- |
| `firstName`           | `String?` | Customer given name.                                                   |
| `lastName`            | `String?` | Customer family name.                                                  |
| `customerNumber`      | `String?` | Host-application customer number (free-form).                          |
| `email`               | `String?` | Customer email for receipts and reconciliation.                        |
| `phone`               | `String?` | Customer phone, free-form.                                             |
| `customerId`          | `Int?`    | Payabli internal customer ID, when the customer is already registered. |
| `company`             | `String?` | Business name when the cardholder represents an organization.          |
| `billingAddress1`     | `String?` | Billing address — street line 1.                                       |
| `billingAddress2`     | `String?` | Billing address — street line 2.                                       |
| `billingCity`         | `String?` | Billing city.                                                          |
| `billingState`        | `String?` | Billing state or region.                                               |
| `billingZip`          | `String?` | Billing postal code.                                                   |
| `billingCountry`      | `String?` | Billing country (ISO 3166 alpha-2 recommended).                        |
| `billingPhone`        | `String?` | Billing phone (distinct from `phone`).                                 |
| `billingEmail`        | `String?` | Billing email (distinct from `email`).                                 |
| `shippingAddress1`    | `String?` | Shipping address — street line 1.                                      |
| `shippingAddress2`    | `String?` | Shipping address — street line 2.                                      |
| `shippingCity`        | `String?` | Shipping city.                                                         |
| `shippingState`       | `String?` | Shipping state or region.                                              |
| `shippingZip`         | `String?` | Shipping postal code.                                                  |
| `shippingCountry`     | `String?` | Shipping country.                                                      |

`PayabliTTPInvoiceData` (every field optional):

| Field           | Type      | Purpose                                                                |
| --------------- | --------- | ---------------------------------------------------------------------- |
| `invoiceNumber` | `String?` | Invoice reference forwarded to the backend and the processor.          |

A comprehensive example:

```swift
let result = try await ttp.charge(
    type: .sale,
    paymentDetails: PayabliTTPPaymentDetails(
        amount: 24.50,
        serviceFee: 1.00,
        currency: "USD",
        paymentDescription: "Two coffees and a croissant"
    ),
    customer: PayabliTTPCustomerData(
        firstName: "Jane",
        lastName: "Doe",
        customerNumber: "cust-1234",
        email: "jane@example.com",
        phone: "+1 555 0100",
        billingAddress1: "1 Market St",
        billingCity: "San Francisco",
        billingState: "CA",
        billingZip: "94105",
        billingCountry: "US"
    ),
    invoice: PayabliTTPInvoiceData(invoiceNumber: "INV-9001"),
    orderDescription: "Two coffees and a croissant"
)
```

### Session lifecycle

```text
COLD START
──────────────────────────────────────────────────────────────────────
  .idle ─▶ .attestingDevice ─▶ .fetchingConfig ─▶ .initializingReader ─▶ .ready

PENDING-ACTIVATION BRANCH (first-time device)
──────────────────────────────────────────────────────────────────────
  .attestingDevice ─▶ .pendingActivation ─▶ (partner OTP) ─▶ .idle

WARM RESTART (session expired while .ready)
──────────────────────────────────────────────────────────────────────
  .ready ─▶ .sessionExpired ─▶ .reinitializing ─▶ .fetchingConfig ─▶ .initializingReader ─▶ .ready
```

The first launch performs cold attestation: Apple's App Attest
combined with Payabli's `/register` and `/attest` endpoints.
Subsequent launches reuse the cached attestation and refresh `/config`
only.

### Listening for events

The `events()` AsyncSequence emits a play-by-play of session activity,
suitable for driving spinners, analytics, or progress UI:

```swift
for await event in viewModel.ttp.events() {
    switch event {
    case .readerReady:              print("Ready to tap")
    case .nfcStarted:               print("Hold card near iPhone")
    case .updateCompleted(let id):  print("Charge complete: \(id)")
    case .devicePendingActivation:  print("Activation code required")
    default: break
    }
}
```

Multiple subscribers each receive every event.

### Pending device activation

The first time a device runs the application, it may require an
activation code before payments can be accepted. The `initialize()` method throws
`PayabliTTPError.devicePendingActivation` to signal this condition:

```swift
do {
    try await ttp.initialize()
} catch PayabliTTPError.devicePendingActivation {
    let code = await promptForActivationCode()        // host UI
    try await ttp.activateDevice(activationCode: code)
    try await ttp.initialize()                         // retry
}
```

The activation code is issued by the partner backend (typically via an
administrator dashboard); the SDK doesn't generate it. Delivery of
the code to the user is the host application's responsibility.

### Handling errors

`PayabliTTPError` covers the entire session and charge lifecycle:

```swift
do {
    try await ttp.initialize()
    let result = try await ttp.charge(
        type: .sale,
        paymentDetails: PayabliTTPPaymentDetails(amount: 9.99)
    )
} catch PayabliTTPError.devicePendingActivation {
    // First-time device — prompt for activation code.
} catch let PayabliTTPError.invalidState(current, attempted) {
    // Session isn't in the required state for this call.
} catch let PayabliTTPError.attestationFailed(reason) {
    // App Attest or Payabli refused to attest the device.
} catch let PayabliTTPError.nfcFailed(reason) {
    // Card removed prematurely, reader timeout, or similar; usually retryable.
} catch let PayabliTTPError.updateFailed(reason) {
    // /update PATCH failed after retries. Reconcile out of band.
} catch PayabliTTPError.tokenExpired {
    // tokenProvider returned no token; re-authentication required.
}
```

When the SDK is consumed from Objective-C or a bridged framework,
these errors surface as `NSError` instances with domain
`"com.payabli.ttp"` and a stable per-case integer code.

---

## Reference

### Objective-C and cross-platform bridges

The SDK exposes a parallel Objective-C surface. Every Swift
`async throws` method has a callback-based `@objc` companion, structs
have `*ObjC` companion classes, events expose stable integer codes,
and errors bridge to `NSError` with domain `"com.payabli.ttp"`.

```objc
PayabliTTP *ttp = [[PayabliTTP alloc]
    initWithAccessToken:token
    tokenRefreshHandler:^(void (^done)(NSString *, NSError *)) { /* ... */ }
              entryPoint:@"your-entrypoint"
                   appId:@"TEAM123456.com.yourcompany.app"
             environment:PayabliEnvironmentSandbox];

[ttp initializeWithCompletion:^(NSError *err) {
    if (err) { /* handle */ return; }
    PayabliTTPPaymentDetailsObjC *details =
        [[PayabliTTPPaymentDetailsObjC alloc]
            initWithAmount:[NSDecimalNumber decimalNumberWithString:@"9.99"]
                serviceFee:NSDecimalNumber.zero
                  currency:@"USD"
        paymentDescription:nil];
    [ttp chargeWithType:PayabliTTPPaymentTypeSale
        paymentDetails:details
              customer:nil
               invoice:nil
      orderDescription:nil
            completion:^(PayabliTTPTransactionResultObjC *result, NSError *e) {
        NSLog(@"Transaction captured. ID: %@", result.paymentTransId);
    }];
}];
```

Cross-platform host code is provided under `Bridges/Flutter/`,
`Bridges/MAUI/`, and `Bridges/ReactNative/`. See
[Bridges/README.md](./Bridges/README.md) for the current status of
each binding.

### Sample application

A complete SwiftUI sample app is located at [`Example/PayabliDemo`](./Example/PayabliDemo/).
It covers initialization, charge, activation, and a live event log.
Follow these steps to set up the sample app:

```bash
git clone https://github.com/payabli/sdk-ios.git
cd sdk-ios/Example/PayabliDemo
cp Secrets.swift.sample Secrets.swift    # populate with sandbox credentials
```

Tap to Pay on iPhone requires a physical iPhone XS or newer running
iOS 16.7 or later. The simulator doesn't pass the eligibility check.

---

## Support

- Bug reports and feature requests: **support@payabli.com**
- Integration documentation: **<https://docs.payabli.com/ios>**

---

## License

Commercial — see [LICENSE](./LICENSE). The bundled
`PayabliCardReaderCore` engine is MIT-licensed; full attribution is
documented in `THIRD_PARTY_LICENSES.txt`.
