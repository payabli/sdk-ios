# PayabliMauiDemo (TTP-only)

Minimal .NET MAUI demo wrapping the native Tap to Pay on iPhone surface
of `PayabliSDKTapToPay` via the Xamarin.iOS binding library in
`Bridges/MAUI/`.

## What it covers

- **Initialize** — runs the cold/warm App Attest + `/config` + reader
  prepare pipeline via `PayabliTTP.Initialize(...)`.
- **Charge** — full sale via `PayabliTTP.Charge(...)` with NFC tap.
- **Activate device** — pending-device activation with an out-of-band
  code.
- **Live event log** — every `PayabliTTPEvent` from `AddEventListener`
  rendered into a scrollable label.
- **Session badge** — current `PayabliTTPSessionState` shown in the
  page header.

## Setup

1. Build the three release XCFrameworks (run from the repo root):
   ```bash
   ./Scripts/build_release_frameworks.sh
   ```
2. Drop the output XCFrameworks into `Bridges/MAUI/Frameworks/`:
   ```bash
   mkdir -p Bridges/MAUI/Frameworks
   cp -R build/release/PayabliSDKCore.xcframework        Bridges/MAUI/Frameworks/
   cp -R build/release/PayabliSDKTapToPay.xcframework    Bridges/MAUI/Frameworks/
   cp -R build/release/PayabliCardReaderCore.xcframework Bridges/MAUI/Frameworks/
   ```
3. Restore and build the demo:
   ```bash
   cd Example/PayabliMAUIDemo
   dotnet restore
   dotnet build -f net8.0-ios17.0
   ```
4. Wire `FetchAccessTokenFromPartnerBackend()` in `MainPage.xaml.cs` to
   your backend's `/payabli/token` endpoint and update the `Secrets`
   constants (`EntryPoint`, `AppId`).
5. Run on a physical iPhone XS or newer.

## Required iOS entitlements (host app)

Add to your MAUI iOS entitlements file:

| Entitlement | Value |
|---|---|
| `com.apple.developer.proximity-reader.payment.acceptance` | `true` |
| `com.apple.developer.devicecheck.appattest-environment` | `production` (or `development`) |

You also need to:
- Enable **Tap to Pay on iPhone** capability in your Apple Developer
  account for the bundle identifier.
- Set `Secrets.AppId` in `MainPage.xaml.cs` to `<TEAM_ID>.<BUNDLE_ID>`.

## Hardware requirement

Tap to Pay only works on **physical iPhone XS or newer running iOS
16.7+**. Trying to run on the Simulator will fail at the eligibility
gate during `Initialize`.

## Not included in the scaffold

The full MAUI project (`Platforms/iOS/AppDelegate.cs`, `MauiProgram.cs`,
etc.) — generate with `dotnet new maui` then drop in this
`MainPage.xaml`, `MainPage.xaml.cs`, and the existing
`PayabliMauiDemo.csproj`. The csproj already references
`Bridges/MAUI/Payabli.MAUI.csproj` as the binding library.
