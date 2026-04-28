# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
swift build -v                    # Build all targets
swift test -v                     # Run all test targets
swift test --filter <TestClass>   # Run a single test class
swift test --filter <TestClass/testMethod>  # Run a single test
./Scripts/build_framework.sh      # Build universal XCFramework → build/PayabliSDK.xcframework
pod lib lint PayabliSDK.podspec   # Validate CocoaPods distribution spec
swiftlint                         # Lint (config: .swiftlint.yml)
swiftformat .                     # Format (config: .swiftformat)
```

CI runs on macOS 14 / Xcode 15.2 via `.github/workflows/ci.yml`.

## Module Architecture

Three Swift package targets, all dynamic frameworks (PRD NFR-11):

**PayabliSDKCore** — Zero external dependencies (NFR-8). Shared infrastructure used by all other modules:
- `PayabliAuth` (actor): token storage with in-flight refresh deduplication; never logs tokens
- `PayabliService`: pure HTTP transport — no auth state, returns raw or decoded responses
- `PayabliRequest` / response envelopes: two envelope shapes exist — legacy `PayabliEnvelope` (attestation/device endpoints) and `PayabliV2Envelope<T>` (MoneyIn v2 endpoints)
- `PayabliComponent` protocol: static requirements (componentId, sessionTier, requiredPermissions) used for lifecycle uniformity across all components
- `PayabliLogger`: wraps `os.Logger` with explicit `.public`/`.private` privacy levels — PANs, tokens, CVVs, account numbers are never logged

**PayabliSDKPayIn** — Depends on Core + FiservTTP (iOS-only, platform-conditional):
- `PayabliPayIn` (singleton facade, aliased as `PayabliClient`)
- SwiftUI forms: `PaymentFormView` backed by `CardFormViewModel` / `ACHFormViewModel` (@MainActor, @ObservableObject); on-blur validation only shows errors for touched fields
- `GetpaidClient`: card/ACH/Apple Pay via `POST /api/v2/MoneyIn/getpaid`
- `TokenStorageClient`: payment method tokenization
- **Tap to Pay**: `PayabliTTP` (main facade split across 3 companion files per §7.2 — `+Initialize`, `+Activation`, `+Charge`), `FiservCardReader` adapter, `AppAttestService` (App Attest + Keychain), 9-state `SessionManager`. No offline retry: if the final `PATCH /update` fails, `charge()` throws `PayabliTTPError.updateFailed` and partners reconcile manually.

**PayabliSDKTelemetry** — Depends on Core only. Optional observability with Sentry and PostHog transports (bring-your-own-instance). Opt-out via `PayabliConfig.telemetryEnabled`.

## Key Design Patterns

**Error hierarchy**: `PayabliError` protocol → concrete types (`PayabliGenericError`, `PayabliValidationError`, `PayabliServerError`, `PayabliDeclineError`) → `PayabliPaymentError` umbrella enum for payment flows. HTTP status mapping: 400→validation, 401→tokenExpired (triggers refresh), 402→decline, 403→permissionDenied, 410→sessionBurned, 500+→server.

**Auth flow**: On 401, `PayabliAuth.invalidateAndRefresh()` calls the host app's `PayabliConfig.tokenProvider()` callback. Concurrent 401s are deduplicated via a stored `Task` (`inFlightRefresh`).

**Companion files**: Large facades are split across `+Extension.swift` files (e.g., `PayabliTTP+Initialize.swift`, `PayabliTTP+Charge.swift`). This is intentional per PRD §7.2 — don't consolidate them.

**Platform gating**: `FiservTTP` is iOS-only via `.when(platforms: [.iOS])` in Package.swift, so macOS builds compile without TTP. Guard TTP-specific code with `#if canImport(FiservTTP)` or `#if os(iOS)`.

**Secure storage**: `SecureStorage` protocol abstracts Keychain access; inject stubs in tests rather than hitting real Keychain.

**TTP state machine**: 9 states — idle, attesting, ready, reading, charged, declined, cancelled, error, reinitialized. State transitions are published via `@Published sessionState` on `PayabliTTP`.

## Testing

- `StubURLProtocol` is the HTTP mocking primitive — register stubs before tests, don't mock `URLSession` directly
- Integration tests wire real `PayabliAuth` + `PayabliService` against stubbed HTTP
- Use `@testable import` to access internal types
- TTP and Apple Pay tests must run on physical device or use mocks for `DCAppAttestService`

## Bridging (non-SPM)

`Bridges/` contains Flutter (MethodChannel), .NET MAUI, and React Native wrappers. These are not compiled as part of the Swift package — they're consumed by their respective host toolchains and should not be modified as part of Core/PayIn work.

## Reference

- `RFC-0001-payabli-sdk-ios.md` — implementation roadmap and architecture decisions; consult before changing module boundaries or error model
- `Example/PayabliDemo/` — requires `Config.xcconfig` (copy from `.sample` and fill sandbox credentials)
