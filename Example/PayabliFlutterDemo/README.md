# PayabliFlutterDemo (TTP-only)

Minimal Flutter app wrapping the native Tap to Pay on iPhone surface of
`PayabliSDKTapToPay` via the MethodChannel + EventChannel bridge in
`Bridges/Flutter/`.

## What it covers

- **Initialize** — runs the cold/warm App Attest + `/config` + reader
  prepare pipeline.
- **Charge** — full sale via `PayabliTTP.charge(paymentDetails:)` with NFC tap.
- **Activate device** — pending-device activation with an out-of-band
  code.
- **Live event log** — every `PayabliTTPEvent` from the EventChannel
  rendered into a list.
- **Session badge** — current `PayabliTTPSessionState` color-coded in
  the app bar.

## Setup

1. Install Flutter 3.16+ and run `flutter doctor`.
2. The bridge in `Bridges/Flutter/` is referenced as a path dependency in
   `pubspec.yaml`. To make it importable as a `payabli_sdk` package, scaffold
   a Flutter plugin around it:
   ```bash
   cd Bridges/Flutter
   flutter create --template=plugin --platforms=ios --org com.payabli .
   # Then drop in the existing payabli_sdk.dart (move to lib/) and
   # PayabliSDKPlugin.swift (move to ios/Classes/).
   ```
3. From this directory, `flutter pub get`, then run on a physical iPhone:
   ```bash
   flutter run -d <device-id>
   ```
4. Edit `lib/main.dart`'s `Secrets` class to point at your partner backend
   `/payabli/token` endpoint.

### Required iOS entitlements (host app)

Add to `ios/Runner/Runner.entitlements` (create if missing):

| Entitlement | Value |
|---|---|
| `com.apple.developer.proximity-reader.payment.acceptance` | `true` |
| `com.apple.developer.devicecheck.appattest-environment` | `production` (or `development`) |

You also need to:
- Enable **Tap to Pay on iPhone** capability in your Apple Developer
  account for the bundle identifier.
- Set `Secrets.appId` in `lib/main.dart` to `<TEAM_ID>.<BUNDLE_ID>`.

### Hardware requirement

Tap to Pay only works on **physical iPhone XS or newer running iOS
16.7+**. The Simulator will fail at the eligibility gate during
`initialize()`.

## Architecture notes

- `PayabliTTP.configure()` sets up the underlying Swift `PayabliTTP`
  instance and wires the Dart-side `tokenProvider` callback to the
  native `refreshToken` MethodChannel callback. Token refresh stays
  end-to-end in your code.
- Lifecycle events arrive via `PayabliTTP.events()` — a broadcast
  `Stream<PayabliTTPEvent>` backed by the EventChannel. Each event
  carries a `code` (typed `PayabliTTPEventCode` enum) and a `payload`
  map (per-case schema documented in the bridge source).
- Errors thrown by the SDK surface as `PayabliTTPException` with the
  stable code `TTP_<n>` for typed `PayabliTTPError`s — see the native
  module README for the code table.
