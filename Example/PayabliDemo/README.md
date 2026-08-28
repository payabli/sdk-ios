# PayabliDemo

SwiftUI demo app exercising the public `PayabliTTP` and
`PayabliPayInPaymentFlowView` APIs, covering card-present and card-not-present
end to end against sandbox.

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
- **Session badge** — the navigation bar shows where the reader has got to,
  color-coded, as `TapToPaySessionStatus`: the SDK's nine states in this app's
  own words.
- **PayIn payment flow** — SwiftUI `PayabliPayInPaymentFlowView` tabs that can
  render stored-method and capture forms, hide optional values, apply a custom
  style, and return token-storage or MoneyIn API responses.

## Setup

1. Open `PayabliDemo.xcodeproj`.
2. Copy `App/Configuration/Secrets.swift.sample` to `Secrets.swift` beside it and
   fill in your sandbox
   credentials. `Secrets.swift` is gitignored.
3. Set `DEVELOPMENT_TEAM` on the target, and set `Secrets.appId` to
   `<TEAM_ID>.com.payabli.example.app`. The Tap to Pay tab flags a
   mismatch on screen rather than letting App Attest reject it later.

```bash
xcodebuild build -project PayabliDemo.xcodeproj -scheme PayabliDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Why the target links one aggregate product

The target links the private `PayabliSDKExampleAggregate` product rather than
`PayabliSDKTapToPay` and `PayabliSDKPayInPaymentFlow` separately. Linking two
dynamic products that both need the `PayabliSDKCore` **target** makes Xcode try
to hoist that target into its own dynamic library, which collides with the
same-named `PayabliSDKCore` **product**:

```text
error: Swift package target 'PayabliSDKCore' is linked as a static library by
'PayabliDemo' and 'PayabliSDKPayInPaymentFlow', but cannot be built dynamically
because there is a package product with the same name.
```

One aggregate product is one dylib, so there is nothing to hoist. This is a
demo-host workaround and **not** how an integrator links the SDK: a real app
links the individual capability products, which is what keeps a card-not-present
app from linking the card reader engine at all.

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

The PayIn payment flow tabs can be visually exercised in the Simulator.
Submitting either form requires the sample's PayIn access-token callbacks to
call your backend or the bundled `LocalTokenServer` for a short-lived Payabli
access token.

### PayIn payment flow diagnostics

The sample uses the public `PayabliPayInPaymentFlow` initializers and the
SDK-owned transport path. This preserves the hosted-form security model: clear
PAN is not exposed to host-visible text fields, accessibility values,
diagnostics, callbacks, or custom transports.

For local debugging, enable the PayIn diagnostics flag in `Secrets.swift`.
Diagnostics are redacted before they are printed or displayed in the app.

## Architecture notes

The entry point is **`App/PayabliDemoQAApp.swift`**, a four-tab `TabView`:
**Save · Capture · TapToPay · Config**. It holds two PayIn flow handles
(stored-method and capture) and one terminal handle as `@StateObject`s, each built
by `SDK/`, and passes them into their tabs. That is the whole file: the flows
themselves, the diagnostics wiring and the form configuration live in `SDK/`.

```
PayabliDemo/
  SDK/            every call this app makes into the SDK, and nothing else
                  PayInSessions.swift           builds the two card-not-present flows
                  PayInFlowHandle.swift         owns one flow, hands screens answers
                  PayInForms.swift              what each form collects
                  PayInRequests.swift           what a capture attempt asks for
                  PaymentFormHost.swift         where the SDK's form mounts
                  PayInOutcome.swift            the app's own result and failure
                  PayInDiagnostics.swift        the redacted request log
                  TapToPaySessions.swift        builds the card reader
                  TapToPayTerminal.swift        owns the reader, hands screens answers
                  TapToPaySessionStatus.swift   the nine states, in this app's words
                  PayabliEnvironmentMapping.swift  the demo's environment, in the SDK's terms
                  DemoCustomerData.swift        the stand-in customer each surface sends
                  PayInSharedConfiguration.swift  what both forms share
                  LoggableError.swift           what a log line may say about a failure
  App/            PayabliDemoQAApp.swift        @main + the tab shell
    Configuration/  ConfigurationQAView.swift   the Config tab
                    DemoEnvironment.swift       the environments this app offers
                    DemoConfiguration.swift     which one runs, and the token host
                    EntryPointLookup.swift      which paypoint each one uses
                    Secrets.swift               credentials only (gitignored)
                    TokenServerHealth.swift
    TapToPay/       PaymentTapToPayQAView.swift
                    TapToPayPreflight.swift     the checks
                    TerminalReadinessView.swift the verdict
    PayIn/          PaymentMethodQAView.swift, PaymentCaptureQAView.swift,
                    PaymentMethodAddedView.swift
    Flow/           the step sequences each screen renders
    Diagnostics/    DiagnosticsStore.swift, DiagnosticsSection.swift
    Debug/          DebugPrefill.swift, DebugPrefill.json
    Shared/         rows, identity, amounts, token probes
    Theme/          the palette
  Config/         *.xcconfig                    build settings, per configuration
  Resources/      Info.plist, PayabliDemo.entitlements
  Scripts/        check-sdk-linkage.sh
  LocalTokenServer/  Node token broker
```

`SDK/` is the point of this layout. Every call into `PayabliSDKCore`,
`PayabliSDKTapToPay` and `PayabliSDKPayInPaymentFlow` is in there, and nothing
outside it imports an SDK module, so the answer to "how do I call this thing" is
one directory rather than a search through the screens. Keeping it that way is a
placement rule this app follows, not something a build step checks: a new call
into the SDK belongs in `SDK/`, and a screen that needs an answer from it gets
one of this app's own types. The Android sample follows the same rule in
`example/src/main/java/com/payabli/example/app/sdk/`.

The screens hold this app's own types. A form's result reaches a screen as
`PayInOutcome`, a failure as `PayInFailure`, and the reader's state as
`TapToPaySessionStatus`, each translated at the boundary.

The environment works the same way and is worth calling out, because it is the one
an integrator changes first. This app owns `DemoEnvironment` and decides which one
runs; `SDK/PayabliEnvironmentMapping.swift` says what the SDK calls it, and nothing
above holds an SDK environment to point a session somewhere. The Android sample
splits it the same way, mapping in `app/sdk/PayInSessionSource.kt`.

### The Config tab

Read-only. The SDK captures `entryPoint`, `environment` and `appId` at launch,
so an editable field would show a value it never received. Edit `Secrets.swift`
and relaunch.

It shows Integration, Token endpoint (with **Check token** and **Health**
probes), card-present readiness, the shared card-not-present settings, the
diagnostics toggles, and a Build section carrying the bundle ID, signing team,
device, host kind, SDK linkage and SDK version. The card-not-present rows read
from `PayInSharedConfiguration` — the same source the forms use — so the screen
cannot drift from real behaviour.

### Terminal readiness

`TerminalReadinessView` reports a verdict and **only the reasons it is not
ready**: **Terminal Ready** in green, or **Terminal Not Available** in red with
the blocking rows listed. A passing check is not news, so passing rows never
render and a fully-working terminal collapses to one green line.

The rollup lives in `TapToPayPreflight.readiness(from:)` rather than in a view,
so the TapToPay tab and the Config tab cannot reach different conclusions from
the same facts. `Check.Status` is deliberately not `Comparable` — the checks are
independent, with no meaningful ordering — so the rollup is stated explicitly:
not-available if and only if something hard-failed. A `.warn` or `.unknown` is a
caveat, not a blocker.

`TapToPayPreflight` still answers each question on its own, which is the property
that makes one rolled-up verdict trustworthy. Nothing in it reaches the network
or reads a secret.

| Check | Source | Independent of |
|---|---|---|
| Simulator vs physical device | `targetEnvironment(simulator)`, `SIMULATOR_DEVICE_NAME`, `uname` | team, token, entitlement |
| App Attest availability | `DCAppAttestService.shared.isSupported` | entitlement, token |
| Reader hardware | `PaymentCardReader.isSupported` | team, token |
| Tap to Pay entitlement | `embedded.mobileprovision` → `Entitlements` | token, `Secrets` |
| App ID correctness | profile Team ID vs `Secrets.appId` vs bundle ID | token |

Two traps this exists to avoid. **The Simulator answers
`PaymentCardReader.isSupported == true`**, so that flag alone reads as ready on a
host that can neither attest nor read a card; the report cross-references it
against host kind and downgrades it to a warning. And a **missing embedded
profile is reported as "unknowable", never as "entitlement absent"** — a
Simulator build has no profile, so treating that as a failure would be wrong.

The provisioning profile is parsed once per process, not per SwiftUI body
evaluation, and the checks are recomputed on appearance or via **Re-check**.

### The token-server host is resolved at runtime, not pinned

`127.0.0.1` means the Mac in the Simulator and the phone on a device, so the host
cannot be a constant. `DemoConfiguration.TokenServer` picks it per run:

| Order | Condition | Host |
|---|---|---|
| 1 | `-PayabliTokenHost <host>` launch argument, or the same `UserDefaults` key | whatever you pass |
| 2 | Simulator | `127.0.0.1` |
| 3 | Physical device | `Secrets.localNetworkHost` |

The override takes a bare host, `host:port`, or a full URL, and needs no rebuild.
In Xcode it goes in **Product → Scheme → Edit Scheme → Run → Arguments**.

`Secrets.localNetworkHost` defaults to the Mac's Bonjour name
(`scutil --get LocalHostName`) rather than an IP, so a DHCP lease change does not
quietly break device testing. The hostname itself can still drift, and a stale one
fails exactly as a stale IP would.

`NSLocalNetworkUsageDescription` is in `Info.plist` because iOS gates mDNS and
local-subnet traffic behind the Local Network prompt. The Config tab prints the
resolved endpoint and which rule produced it, so the active host is never a guess.

**Running against a physical device has several traps that all present as network
failures and are not** — how to bind the server, why `.local` can fail only
on-device, and why the Local Network grant resets on a bundle-id change. They are
documented once, next to the server they concern:
[`LocalTokenServer/README.md`](LocalTokenServer/README.md#simulator-vs-physical-device).

### SDK linkage

The demo compiles the SDK from `Package.swift` on every build. The active mode
comes from `PAYABLI_SDK_LINKAGE` in the build configuration, is echoed into the
build log by the **Payabli SDK linkage** phase, and is surfaced in the Config
tab's Build section.

| Configuration | `PAYABLI_SDK_LINKAGE` | Behaviour |
|---|---|---|
| `Debug` (default) | `source` | compiles the SDK as part of the build |
| `Release` | `source` | same |
| `Debug-XCFramework` | `xcframework` | **fails closed** — not wired yet |

`Debug-XCFramework` is a hook, not a working mode: every build with it fails on
purpose rather than quietly falling back to source.

It cannot work as one configuration. Which products a target links is set on the
target, so switching configuration cannot unlink the package and would leave the
build linking both the package sources and any framework it found. A second
target that links the frameworks instead is what makes it real, and that belongs
with the binary-release work.

## Not included

- A real partner backend. `Secrets.swift.sample` points the two token endpoints at
  a placeholder partner backend, so a fresh clone repoints them at the bundled
  `LocalTokenServer` and gives that server its own sandbox credentials.
- A Tap to Pay provisioning profile. Without the Apple-granted
  `com.apple.developer.proximity-reader.payment.acceptance` entitlement the app
  still builds and the TapToPay tab still renders, but **Enable Terminal**
  cannot reach `.ready`.
