# PayabliDemo

SwiftUI demo app exercising the public `PayabliTTP` and
`PayabliTokenizationView` APIs. Maps to the Tap to Pay manual QA checklist
and includes a card/ACH tokenization sample.

## What it covers

- **Initialize** — cold/warm App Attest attestation, `/config` fetch, and
  reader prepare via `try await ttp.initialize()`.
- **Re-initialize** — silent recovery from `.sessionExpired` /
  `.idle` / `.error` via `ttp.reinitializeIfNeeded()`.
- **Charge** — full sale pipeline (`/initiate` → NFC tap → `/update`)
  via `try await ttp.charge(type:paymentDetails:)`.
- **Activate device** — pending-device activation with an out-of-band
  code via `ttp.activateDevice(activationCode:)`.
- **Live event log** — every `PayabliTTPEvent` from the multicaster
  rendered into a list, including the per-case payload.
- **Session badge** — the navigation bar shows the current
  `PayabliTTPSessionState` color-coded.
- **Tokenization** — a SwiftUI `PayabliTokenizationView` tab that can render
  card and ACH forms, hide optional values, apply a custom style, and return
  the full token-storage API response.

## Setup

1. Open Xcode and create a new **iOS App** project named `PayabliDemo` at
   this directory. Choose **SwiftUI** for the interface and **Swift** for
   the language.
2. Add the local Swift package dependency:
   - **File → Add Packages → Add Local…** and select the repository root.
   - Pick the `PayabliSDKTapToPay` and `PayabliSDKTokenization` products
     (not the umbrella `PayabliSDK`, unless you also need `PayabliSDKCore`
     types directly).
3. Drag `PayabliDemoApp.swift` and `HomeView.swift` into the Xcode project.
4. Copy `Secrets.swift.sample` to `Secrets.swift` and fill in your sandbox
   credentials. `Secrets.swift` is gitignored.

### Required entitlements

Tap to Pay on iPhone needs two Apple entitlements that you must add to the
host app target's entitlements file:

| Entitlement | Value | Notes |
|---|---|---|
| `com.apple.developer.proximity-reader.payment.acceptance` | `true` | Apple grants this on request — see [Setting Up the Entitlement](https://developer.apple.com/documentation/proximityreader/setting-up-the-entitlement-for-tap-to-pay-on-iphone) |
| `com.apple.developer.devicecheck.appattest-environment` | `production` (or `development` for dev builds) | Required by App Attest for cold-start attestation |

You also need to:
- Enable **Tap to Pay on iPhone** capability in your Apple Developer
  account for the bundle identifier.
- Set `Secrets.appId` to `<TEAM_ID>.<BUNDLE_ID>` so attestation can
  verify the binary.

### Hardware requirement

Tap to Pay only works on **physical iPhone XS or newer running iOS
16.7+**. The demo will fail at the eligibility gate when run on the
Simulator (you'll see a `notReady` error early in `initialize()`).

The tokenization tab can be visually exercised in the Simulator. Submitting
the form requires `Secrets.fetchTokenizationAccessToken()` to call your backend
for a short-lived Payabli access token.

## Architecture notes

`PayabliDemoApp` owns one `PayabliTTP` instance and one
`PayabliTokenization` instance as `@StateObject`s and injects both into
`HomeView` via `@EnvironmentObject`. The Tap to Pay view
subscribes to the event stream in `onAppear` (via `events()` plus a
sentinel `addEventListener` token used purely for tear-down on
`onDisappear`) and updates UI state from the `@Published`
`sessionState` and `isReady` properties.

The tokenization tab renders `PayabliTokenizationView` with:
- `allowedMethods: [.card, .ach]`
- required card ZIP input
- hidden optional values for ACH holder type and method description
- `labelLayout: .external`
- configurable submit button text
- per-field input sizing
- `.payabliTokenizationStyle(...)` to demonstrate host-controlled styling

Token refresh is handled inside the SDK: when the access token expires,
`PayabliTTP` invokes the `tokenProvider` closure passed at init, which
the demo wires to `Secrets.fetchAccessToken()`. Replace that with a call
to your own backend in production.

Tokenization access tokens use a separate backend callback:
`Secrets.fetchTokenizationAccessToken()`. Keep private Payabli API credentials
on your server, never in the mobile app binary.

## Not included in this scaffold

- Xcode project files (`.xcodeproj`) — generate locally per the steps
  above.
- A real partner backend — the `Secrets.fetchAccessToken()` URL is a
  placeholder you must replace.
