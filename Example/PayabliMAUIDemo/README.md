# PayabliMauiDemo

Minimal .NET MAUI demo wrapping Tap to Pay and payment method through the
.NET iOS binding library in `Bridges/MAUI/`.

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
- **Card and ACH payment method** — sample forms calling
  `PayabliPaymentMethodObjC.AddCard(...)` and
  `PayabliPaymentMethodObjC.AddACH(...)`, then rendering the
  stored-method response.

## Setup

1. Build the release XCFrameworks (run from the repo root):
   ```bash
   ./Scripts/build_release_frameworks.sh
   ```
2. Drop the output XCFrameworks into `Bridges/MAUI/Frameworks/`:
   ```bash
   mkdir -p Bridges/MAUI/Frameworks
   cp -R build/release/PayabliSDKCore.xcframework        Bridges/MAUI/Frameworks/
   cp -R build/release/PayabliSDKTapToPay.xcframework    Bridges/MAUI/Frameworks/
   cp -R build/release/PayabliSDKPaymentMethod.xcframework Bridges/MAUI/Frameworks/
   cp -R build/release/PayabliCardReaderCore.xcframework Bridges/MAUI/Frameworks/
   ```
3. Restore and build the demo with the .NET 10 iOS workload:
   ```bash
   cd Example/PayabliMAUIDemo
   dotnet restore
   dotnet workload restore
   dotnet build -f net10.0-ios
   ```
   If your .NET SDK is installed system-wide, `dotnet workload restore` may
   require elevated privileges. If restore cannot infer workloads from the
   project graph, install them directly:
   ```bash
   sudo dotnet workload install maui-ios mobile-librarybuilder
   ```
4. Wire `FetchAccessTokenFromPartnerBackend()` and
   `FetchPaymentMethodAccessTokenFromPartnerBackend()` in `MainPage.xaml.cs` to
   your backend's Tap to Pay token and payment method access-token endpoints,
   then update the `Secrets` constants (`EntryPoint`, `AppId`).
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

The payment method section can be visually exercised in the Simulator.
Submitting the form requires a valid Bearer access token from your backend for
`/api/TokenStorage/add`.

## Not included in the scaffold

The full MAUI project (`Platforms/iOS/AppDelegate.cs`, `MauiProgram.cs`,
etc.) — generate with `dotnet new maui` then drop in this
`MainPage.xaml`, `MainPage.xaml.cs`, and the existing
`PayabliMauiDemo.csproj`. The csproj already references
`Bridges/MAUI/Payabli.MAUI.csproj` as the binding library.
