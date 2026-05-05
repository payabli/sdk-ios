# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
swift build -v                        # Build all targets
swift test -v                         # Run all test targets
swift test --filter <TestClass>       # Run a single test class
swift test --filter <TestClass/testMethod>  # Run a single test
./Scripts/build_release_frameworks.sh # Build 3 distribution XCFrameworks → build/release/
swiftlint                             # Lint (config: .swiftlint.yml)
swiftformat .                         # Format (config: .swiftformat)
```

No canonical `PayabliSDK.podspec` lives in this repo — the public CocoaPods
spec is produced from `.github/templates/public-PayabliSDK.podspec.tmpl` via
`Scripts/render_public_manifests.sh` (writes `build/public/`), alongside
matching `Package.swift` and `README.md` templates, when publishing binaries.

CI runs on macOS 15 / latest Xcode via `.github/workflows/ci.yml` on **push
and pull_request to `main`**. It resolves SPM deps and runs **`xcodebuild test`
against the root SPM scheme `PayabliSDK-Package`**, not plain `swift test`.

Releases are **manual**: `.github/workflows/release.yml` is triggered with
`workflow_dispatch`. Provide a **semver** `MAJOR.MINOR.PATCH`, optional release
notes; the workflow runs the same tests as CI, creates an **annotated git tag**
for that version, pushes it to `origin`, and opens a **GitHub Release** with
`gh release create`.

## Module Architecture

> **Branch note (`release/ttp-only`):** `PayabliSDKPayIn` and the
> integration-tests target are temporarily removed on this branch so it
> can ship a TTP-only distribution. PayIn lives unchanged on `develop`
> as the live reference for a future re-introduction PR. The folder
> rules below for `PayabliSDKPayIn` still apply when re-introducing
> PayIn — they're kept here for that purpose.

Four Swift package targets on this branch (Core + TapToPay + CardReaderCore
+ Telemetry), all dynamic frameworks (PRD NFR-11). The public SDK ships
**Core + TapToPay + CardReaderCore** as three independent XCFramework
binaries on this branch; on `develop` it ships four (the same plus
PayIn).

**PayabliSDKCore** — Zero external dependencies (NFR-8). Shared infrastructure used by all other modules:

- `PayabliAuth` (actor): token storage with in-flight refresh deduplication; never logs tokens
- `PayabliService`: pure HTTP transport — no auth state, returns raw or decoded responses
- `PayabliRequest` / response envelopes: two envelope shapes exist — legacy `PayabliEnvelope` (attestation/device endpoints) and `PayabliV2Envelope<T>` (MoneyIn v2 endpoints)
- `PayabliComponent` protocol: static requirements (componentId, sessionTier, requiredPermissions) used for lifecycle uniformity across all components
- `PayabliLogger`: wraps `os.Logger` with explicit `.public`/`.private` privacy levels — PANs, tokens, CVVs, account numbers are never logged

**PayabliSDKTapToPay** — Depends on Core + `PayabliCardReaderCore` (iOS-only, platform-conditional). Hosts the entire Tap to Pay on iPhone surface: `PayabliTTP` facade (split across `+Initialize`, `+Charge`, `+Activation` companions), App Attest device attestation, session manager, retry policy, secure storage, and the `TapToPayProvider`/`Adapters/FiservCardReader` provider stack. Flat folder layout (no `TapToPay/` subfolder — the module *is* the TapToPay surface). See `Sources/PayabliSDKTapToPay/README.md` for the full file map.

**PayabliSDKPayIn** — Depends on Core only. Hosts every non-TTP PayIn flow (tokenization, getpaid, Apple Pay, card / ACH forms). Folder rules are below — **when adding a file, pick the folder from the table; don't invent new folders without updating PRD section 7.2**.

**PayabliCardReaderCore** — Vendored MIT-licensed source of `Fiserv/TTPPackage` compiled under the module name `PayabliCardReaderCore`. Source lives under `ThirdParty/PayabliCardReaderCoreSource/Sources/PayabliCardReaderCore/` and is **byte-identical** to upstream; every file preserves the original Fiserv copyright header. The module rename is achieved at the SPM target level only — do not edit class names in the vendored source. To refresh from upstream, replace the vendored Swift files from [`Fiserv/TTPPackage`](https://github.com/Fiserv/TTPPackage) at the desired tag, update the pin table in `ThirdParty/PayabliCardReaderCoreSource/README.md`, and run `swift build` / `swift test` before committing.

**PayabliSDKTelemetry** — Depends on Core only. Optional observability with Sentry and PostHog transports (bring-your-own-instance). Opt-out via `PayabliConfig.telemetryEnabled`.

## Folder Layout (PayabliSDKPayIn)

Strict, per PRD section 7.2. Each folder owns a single concern; cross-folder imports are fine but file placement is not.


| Folder        | What goes here                                                                                                                                                                                                                                                                                                                                                                                             | What does NOT                                           |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `Public/`     | Entry-point facades the host app imports: `PayabliPayIn` singleton + its `+Async` extension, `PayabliClient` typealias, public enums (`PayabliPaymentType`), public option sets (`PayabliCardBrand`), and form-customization strings structs (`CardFormStrings`, `ACHFormStrings`). First surface a consumer types after `import PayabliSDKPayIn`.                                                         | SwiftUI Views, wire DTOs, HTTP clients, platform glue.  |
| `Models/`     | (1) Public data types on the SDK surface (`PayabliPaymentRequest`, `PayabliTransactionResult`). (2) Endpoint-scoped groups: each HTTP client lives **next to** its wire-format DTOs — e.g. `GetpaidClient.swift` + `GetpaidWireFormat.swift`, `TokenStorageClient.swift` + `TokenizationRequest.swift`. (3) Pure cross-flow helpers (`PaymentValidators`).                                                 | SwiftUI, Apple Pay / NFC platform glue, facades.        |
| `Payments/`   | Native platform payment stacks — code that bridges to PassKit / StoreKit / ProximityReader and is driven by the OS framework's control flow. Today: `ApplePayManager`, `PayabliApplePayConfig`.                                                                                                                                                                                                            | HTTP clients (those go in `Models/`), SwiftUI.          |
| `ViewModels/` | SwiftUI `@MainActor ObservableObject` state holders (`CardFormViewModel`, `ACHFormViewModel`). Transient UI state + validation + payload assembly. Testable without presenting a view.                                                                                                                                                                                                                     | HTTP calls, platform APIs, `View` types.                |
| `Views/`      | All SwiftUI Views. Turn-key forms own their VM via `@StateObject` + expose two inits (tokenize vs charge): `CardFormView` (+ `.payabliCardSheet(...)`) and `ACHFormView` (+ `.payabliAchSheet(...)`); sheet modifiers live in the same file as the form. Low-level atoms: `CardBrandBadge`. Shared chrome: `PayabliSheetHeader`. UIKit `UIViewController` factories on `PayabliPayIn` wrap these turn-key views directly — there is no per-type composite view. One principal `View` per file. | Business logic, HTTP, platform glue.                    |


Rules of thumb when unsure:

- "Does the consumer call it by name?" → `Public/`
- "Is it a value type, a DTO, or the HTTP client that owns an endpoint?" → `Models/`
- "Does it wrap an Apple framework that drives the control flow?" → `Payments/` (or `Adapters/` inside `PayabliSDKTapToPay` for NFC)
- "Is it Tap to Pay code (attestation, session, charge, provider)?" → not in PayIn at all — it lives in the `PayabliSDKTapToPay` module
- "Is it `@Published` state for a form?" → `ViewModels/`
- "Is it a `View` or a `ViewModifier`?" → `Views/`

## Key Design Patterns

**Error hierarchy**: `PayabliError` protocol → concrete types (`PayabliGenericError`, `PayabliValidationError`, `PayabliServerError`, `PayabliDeclineError`) → `PayabliPaymentError` umbrella enum for payment flows. HTTP status mapping: 400→validation, 401→tokenExpired (triggers refresh), 402→decline, 403→permissionDenied, 410→sessionBurned, 500+→server.

**Auth flow**: On 401, `PayabliAuth.invalidateAndRefresh()` calls the host app's `PayabliConfig.tokenProvider()` callback. Concurrent 401s are deduplicated via a stored `Task` (`inFlightRefresh`).

**Companion files**: Large facades are split across `+Extension.swift` files (e.g., `PayabliTTP+Initialize.swift`, `PayabliTTP+Charge.swift`, `PayabliPayIn+Async.swift`). This is intentional per PRD section 7.2 — don't consolidate them. Companion files live in the same folder as their principal type.

**Platform gating**: `PayabliCardReaderCore` is iOS-only via `.when(platforms: [.iOS])` in Package.swift, so macOS builds compile without TTP. Guard TTP-specific code with `#if canImport(PayabliCardReaderCore)` or `#if os(iOS)`.

**Secure storage**: `SecureStorage` protocol abstracts Keychain access; inject stubs in tests rather than hitting real Keychain.

**TTP state machine**: 9 states — idle, attesting, ready, reading, charged, declined, cancelled, error, reinitialized. State transitions are published via `@Published sessionState` on `PayabliTTP`.

## Testing

- `StubURLProtocol` is the HTTP mocking primitive — register stubs before tests, don't mock `URLSession` directly
- Integration tests wire real `PayabliAuth` + `PayabliService` against stubbed HTTP
- Use `@testable import` to access internal types
- TTP and Apple Pay tests must run on physical device or use mocks for `DCAppAttestService`

## Top-level folder rules

| Folder          | Purpose                                                                                                                                                                                                                             |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Sources/`      | First-party Payabli code across `PayabliSDKCore`, `PayabliSDKPayIn`, `PayabliSDKTapToPay`, `PayabliSDKTelemetry`. Module-scoped folder rules per `PayabliSDKPayIn` above; `PayabliSDKTapToPay` keeps a flat layout (see `Sources/PayabliSDKTapToPay/README.md`).            |
| `ThirdParty/`   | Vendored MIT / Apache source from upstream projects, kept byte-identical. Today: `PayabliCardReaderCoreSource/` (upstream [`Fiserv/TTPPackage`](https://github.com/Fiserv/TTPPackage); contract in `ThirdParty/PayabliCardReaderCoreSource/README.md`). Each subfolder **must** carry a `README.md` documenting the vendoring contract. |
| `Scripts/`      | `build_release_frameworks.sh` (XCFramework zips → `build/release/`), `render_public_manifests.sh` (templates → `build/public/`), `upload_release.sh` (upload `build/release/` zips to S3 when credentials are configured). |
| `.github/`      | CI (`ci.yml`), release (`release.yml`), and `templates/public-*.tmpl` inputs for `render_public_manifests.sh`.                                                                                         |
| `Tests/`        | `XCTest` targets per module plus `PayabliSDKIntegrationTests` (requires `PAYABLI_SANDBOX_*` env vars).                                                                                                                               |
| `Example/`      | `PayabliDemo` sample app (Xcode project uses the `PayabliTTP` scheme); CI builds/tests the repo-root **`PayabliSDK-Package`** scheme instead.                                                                                                                      |
| `Bridges/`      | Flutter / .NET MAUI / React Native bridge code, consumed by their respective host toolchains. Not built by `swift build`.                                                                                                          |
| `THIRD_PARTY_LICENSES.txt` | MIT attribution for every vendored dependency. Required to ship alongside the distribution zip.                                                                                                                                     |

**Versioning:** There is no checked-in `VERSION` file. Release versions are **explicit semver strings** passed into the Release workflow; CI does not auto-bump patch from commit count.

## Bridging (non-SPM)

`Bridges/` contains Flutter (MethodChannel), .NET MAUI, and React Native wrappers. These are not compiled as part of the Swift package — they're consumed by their respective host toolchains and should not be modified as part of Core / PayIn / TapToPay work.

## Reference

- `README.md` — consumer-facing overview and repo layout for this branch
- `ThirdParty/PayabliCardReaderCoreSource/README.md` — vendoring contract for the Fiserv TTP MIT source
- `Example/PayabliDemo/` — requires `Config.xcconfig` (copy from `.sample` and fill sandbox credentials)
