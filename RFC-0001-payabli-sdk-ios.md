# RFC-0001: PayabliSDK iOS — v1.0 Implementation


| Field              | Value                                                 |
| ------------------ | ----------------------------------------------------- |
| **RFC**            | 0001                                                  |
| **Titlettp**       | PayabliSDK iOS v1.0 implementation (PayIn component)  |
| **Status**         | Draft                                                 |
| **Author**         | [francisco@payabli.com](mailto:francisco@payabli.com) |
| **Created**        | 2026-04-20                                            |
| **Target release** | PayabliSDK 1.0.0                                      |
| **Related**        | PRD "IOS Payment Acceptance" (§1–§28)                 |


---

## 1. Summary

This RFC proposes the implementation strategy for **PayabliSDK 1.0.0**, a native iOS SDK delivering Payabli's PayIn component: tokenization, card-not-present payment processing (`getpaid`), and card-present Tap to Pay on iPhone. The SDK ships in Swift 5.9 for iOS 15+ (iOS 16.7+ for Tap to Pay), distributed as an XCFramework via Swift Package Manager and CocoaPods, and is architected as a **component suite** so Payout, Reporting, and Onboarding components can be added in later releases without disrupting host integrations.

The work is divided into 11 phases (0–10). Phases 0–3 and 5–6 form the critical path to a shippable v1.0; phases 4, 7, 8, and 9 are parallelizable; phase 10 is release hardening.

## 2. Motivation

Host applications that accept payments on iOS face two distinct problems (PRD §2):

1. **Card-not-present:** PCI-DSS compliance burden from handling raw card data and orchestrating tokenization/capture flows against Payabli's API.
2. **Card-present:** Apple's Tap to Pay on iPhone requires coordinating `DCAppAttestService`, ProximityReader, a payment processor SDK (Fiserv), and a multi-step transaction API with crash/network resilience.

Without a first-party SDK, every partner reimplements SwiftUI forms, client-side validation, auth token lifecycle, Apple Pay, App Attest, and retry logic. This is error-prone, expensive, and produces inconsistent user experience across integrations.

A sanctioned SDK reduces integration time to < 30 minutes (PRD §23.4), eliminates raw-card data from host apps (PCI scope reduction, NFR-1..5), and gives Payabli a controlled surface for observability (§24) and future platform evolution (Tier 1/Tier 2 session JWTs — §16).

## 3. Scope

### 3.1 In scope (v1.0)

- `PayabliSDKCore`: auth, networking, theming, telemetry, shared error types, logging
- `PayabliSDKPayIn`: tokenization (card, ACH, Apple Pay), payment processing (`getpaid`), Tap to Pay (Fiserv adapter)
- Client-credentials OAuth2 auth flow (§5.3 FR-6A)
- SwiftUI drop-in forms with on-blur validation and `PayabliTheme` customization
- Device attestation via `DCAppAttestService` with challenge/register/attest flow (§18)
- Retry policy for transient backend failures (§21.1)
- 9-state TTP session state machine (§17) and lifecycle event stream (§20)
- Optional `PayabliSDKTelemetry` module (PostHog + Sentry)
- Cross-platform bridge architecture for Flutter, MAUI, React Native (native module + bindings for Flutter and MAUI; RN architecture only, per FR-9.1)
- Distribution: SPM, CocoaPods, signed XCFramework with `PrivacyInfo.xcprivacy`

### 3.2 Out of scope (deferred)

- `PayabliSDKPayout`, `PayabliSDKReporting`, `PayabliSDKOnboarding` components (§28.1 "Future")
- Tier 1/Tier 2 session JWT authentication (§16 — v2.0 roadmap)
- TTP `.auth` / `.refund` / `.void` transaction types (sale-only in v1.0)
- 3DS challenge flow
- React Native example app (architecture only in v1.0)
- `BGTaskScheduler`-based background queue sync
- Localization (English only in v1.0)

## 4. Architecture

The SDK follows MVVM + component suite architecture (PRD §7, §28). A shared `PayabliSDKCore` target provides auth, networking, theming, telemetry, and error types. Each component — `PayabliSDKPayIn` in v1.0 — is a separate SPM target that depends only on core, implements the `PayabliComponent` protocol, and exposes its own facade singleton (`PayabliPayIn.shared`).

This mirrors the web platform's Embedded Components V2 structure and allows future components (Payout, Reporting, Onboarding) to ship independently without changes to core or existing components.

Key invariants:

- **Core has zero third-party dependencies.** Foundation, SwiftUI, and `os` only. Sentry, PostHog, Fiserv SDK are confined to optional adapter/telemetry modules.
- **All components share one auth session.** One `PayabliConfig` → one access token → usable by any component.
- **TTP is provider-agnostic.** `TapToPayProvider` protocol + `TapToPayProviderFactory`; Fiserv is the v1.0 default, but Stripe/Apple-direct can be added without touching the ViewModel or public API (FR-11A.6, FR-11A.7).
- **Secrets live only in RAM.** `clientSecret`, access tokens, Fiserv credentials, card data — never persisted (NFR-5A..D). Keychain holds only non-secret identity (`keyId`, `deviceId`); nothing else persists to disk.

## 5. Detailed design — phased implementation

Phases are ordered by dependency. Each phase produces a shippable artifact that the next phase depends on, except where noted as parallelizable.

### Phase 0 — Repo & toolchain scaffolding

**Deliverable:** SPM package + podspec skeleton compiles, CI green, nothing functional yet.

- `Package.swift` with targets `PayabliSDKCore`, `PayabliSDKPayIn`, test targets (§28.5)
- Products: umbrella `PayabliSDK` (Core + PayIn) and à-la-carte `PayabliSDKCore` / `PayabliSDKPayIn`
- `PayabliSDK.podspec` with `Core` and `PayIn` subspecs (§28.6)
- Swift 5.9, iOS deployment target 15.0 (PayIn); TTP code gated to iOS 16.7+ via `@available`
- `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`, module stability enabled
- `build_framework.sh` producing universal XCFramework (device arm64 + simulator arm64/x86_64)
- SwiftLint + SwiftFormat config; `PrivacyInfo.xcprivacy` placeholder
- CI: GitHub Actions — `swift build`, `xcodebuild test` on iOS simulator, lint, `pod lib lint`
- `Example/PayabliDemo/` empty SwiftUI scaffold for smoke testing

### Phase 1 — `PayabliSDKCore`

**Deliverable:** Shared foundation every downstream component depends on.

- Public types: `PayabliConfig`, `PayabliTheme`, `PayabliEnvironment`, `PayabliComponent` protocol, `PayabliSessionTier`
- `PayabliAuth`: OAuth2 client credentials flow (§5.3 FR-6A, §8). Actor-based, in-memory token cache, 401 re-acquire
- `PayabliService`: URLSession client, v1/v2 response envelope decoders, token chaining helper, RFC 7807 error mapping
- `PayabliLogger`: `os_log` / `Logger` wrapper with `.private` redaction; subsystem `com.payabli.sdk`, categories per component
- Error hierarchy: `PayabliError`, `PayabliValidationError`, `PayabliServerError`, `PayabliDeclineError` — aligned with §8 error codes
- `@objc NSObject` annotations on public surface (FR-6.6) for Obj-C / MAUI bindings
- Unit tests: token lifecycle, envelope decoding, redaction, token chaining

### Phase 2 — Tokenization (FR-1, FR-2, FR-3, FR-4, FR-5)

**Deliverable:** Drop-in card + ACH tokenization shipping against sandbox.

- `PayabliPayIn` facade (`shared`, `configure`, `createTokenizationViewController`)
- `PayabliPaymentType` enum: `.card`, `.ach` (other cases in later phases)
- SwiftUI forms: `CardFormView`, `ACHFormView`, `PaymentFormView` hosted in `UIHostingController` modal sheet
- ViewModels: `CardFormViewModel`, `ACHFormViewModel` — `ObservableObject`, `@Published` state, touched-field tracking, on-blur validation
- `PaymentValidators`: Luhn, routing checksum, ZIP, CVV, expiration, card brand detection (§10)
- `TokenStorageClient`: `POST /api/TokenStorage/add` (+ `?achValidation=true`)
- `PayabliTheme` wiring (primaryColor, cornerRadius) into SwiftUI tint / `RoundedRectangle`
- Native wheel-picker bottom sheet for expiration (FR-1.6)
- Tests: validators, ViewModel state, model `Encodable` snapshots, integration test against sandbox

### Phase 3 — Payment processing / `getpaid` (FR-12, §9.3A–C)

**Deliverable:** Same forms, authorize+capture via `/api/v2/MoneyIn/getpaid`.

- `PayabliPaymentRequest`, `PayabliTransactionResult` types
- `processPayment(config:theme:type:paymentRequest:completion:)` and `chargeStoredMethod(config:paymentRequest:completion:)` on `PayabliPayIn`
- Idempotency key generation (UUID default, host override via `PayabliPaymentRequest.idempotencyKey`)
- Response classification: approved (`A*`), declined (402, `D*`), validation (400), server (500) — typed errors
- Button label switching ("Save Payment Method" vs "Pay $X.XX")
- Stored-method headless path (no UI, direct API call)
- Tests: response decoding for each envelope variant, stored-method payload shape, idempotency header behavior

### Phase 4 — Apple Pay (FR-10, §9.3) — *parallelizable after Phase 2*

**Deliverable:** `PKPaymentAuthorizationController` integrated into PayIn.

- `PayabliApplePayConfig` (`merchantIdentifier`, networks, capabilities)
- `ApplePayManager` wrapping `PKPaymentAuthorizationController`
- `canMakePayments()` guard with descriptive error on simulator / unsupported devices
- `ApplePayViewModel` extracting `PKPaymentToken.paymentData`, base64-encoding, forwarding to tokenization or `getpaid`
- Cancellation path returns typed cancellation error
- Gated on BR-3, BR-4, BR-5 (Merchant ID, payment processing certificate, domain verification)
- Tests: availability check mocked, token extraction, cancellation

### Phase 5 — Tap to Pay infrastructure (FR-11A, FR-11C–J, §17, §18, §21, §22)

**Deliverable:** Provider-agnostic TTP plumbing ready; no real reader yet (mock provider for tests).

- `TapToPayProvider` protocol, `TapToPayProviderFactory`
- `CardReadResult` value type
- `SessionManager` — 9-state machine (§17) on `@MainActor`, `@Published sessionState`, transition enforcement, `reinitializeIfNeeded()`, `forceSessionExpiry()`
- `DeviceAttestationService` — `DCAppAttestService` integration, challenge → register → attest flow (§18), SHA256 `clientDataHash`
- Keychain storage for `keyId` / `deviceId` (`kSecClassGenericPassword`)
- `RetryPolicy` — 3 attempts, 1s→8s exponential backoff with 0–0.5s jitter (§21.1)
- `EventMulticaster` — `AsyncStream<PayabliTTPEvent>` per caller, multicast fan-out (§20.1)
- `PayabliTTP` facade (`@MainActor`, `ObservableObject`): `initialize()`, `activateDevice(activationCode:)`, `charge(amount:type:)`, `events()`, `isReady`, `sessionState`
- Typed errors (§20.2)
- Mock `TapToPayProvider` for unit tests
- Tests: state machine transitions, retry backoff & jitter bounds, 401 recovery, token chaining, attestation with mocked `DCAppAttestService`

### Phase 6 — Fiserv TTP adapter (FR-11B)

**Deliverable:** Real Fiserv-backed NFC reader behind the Phase 5 protocol.

- `FiservCardReader: TapToPayProvider` wrapping `FiservTTP` package (≥ 1.0.7)
- Lifecycle: configure → linkAccount → prepareSession → nfcCharge → map to `CardReadResult`
- `checkEligibility()`: iOS 16.7+, iPhone XS+, ProximityReader entitlement present
- Runtime-only credential handling — no Keychain / UserDefaults / disk (NFR-5D)
- Session event handling, cancellation, cleanup
- Registration with `TapToPayProviderFactory`
- Gated on BR-2 (TTP entitlement), BR-8, BR-9, BR-10 (Fiserv contract / onboarding / license)
- Instrumented tests on physical iPhone XS+ with iOS 16.7+

### Phase 7 — `PayabliSDKTelemetry` (§24, §26) — *parallelizable after Phase 1*

**Deliverable:** Optional observability, zero PII, opt-out.

- `TelemetryClient`: batched (30s or 20 events), fire-and-forget, schema-versioned envelope, hashed `entry` as distinct ID
- PostHog (`posthog-ios`) — session recording **permanently off** (NFR-24)
- Sentry (`sentry-cocoa`) with **separate `SentryHub` / `SentryClient`** to avoid host-app conflict (NFR-22)
- Event taxonomy from §24.3 (tokenization, TTP lifecycle, system)
- `PayabliConfig.telemetryEnabled = false` suppresses all emission
- Redaction audit: no PAN, CVV, tokens, secrets, unmasked device IDs, names, emails
- Third-party deps kept out of core XCFramework (NFR-26); ship as a separate module
- Tests: batch flush timing, PII scrubbing, opt-out kill switch, Sentry hub isolation

### Phase 8 — `Example/PayabliDemo/` — *grows incrementally alongside Phases 2–5*

**Deliverable:** SwiftUI demo app exercising every public API; doubles as manual-QA harness (§12.3).

- SwiftUI screens: tokenization (card / ACH / Apple Pay), payment (card / ACH / stored), Tap to Pay (init / charge / activation)
- Sandbox credentials via xcconfig / gitignored `Secrets.swift`
- Demonstrates `PayabliConfig`, `PayabliTheme` customization, event stream observation, typed error handling
- Manual QA checklist (§12.3) maps to demo screens

### Phase 9 — Cross-platform bridges (FR-7, FR-8, FR-9) — *parallelizable after Phase 3*

**Deliverable:** Parity for non-native iOS consumers.

- **Flutter:** `MethodChannel` plugin (`com.payabli.sdk/tokenization`), Dart API, example app under `Example/PayabliFlutterDemo/`
- **.NET MAUI:** C# iOS Binding Library (`PayabliBinding`) wrapping the XCFramework, strongly-typed wrappers, example under `Example/PayabliMAUIDemo/`
- **React Native:** Native Module architecture only in v1 per FR-9.1 — confirm `@objc` surface is Dictionary/JSON-bridgeable

### Phase 10 — Release hardening

**Deliverable:** Publishable via SPM + CocoaPods trunk.

- `PrivacyInfo.xcprivacy` completed (BR-19) — required-reason APIs (UserDefaults, disk access), tracking domains (PostHog/Sentry), data collected
- Signed universal XCFramework with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`
- SPM binary target checksum + GitHub Releases asset
- CocoaPods trunk publish (umbrella + subspecs)
- LICENSE + NOTICE files, third-party attributions (BR-20)
- PCI SAQ-A guidance doc for partners (BR-13)
- Release runbook: version tagging, changelog, pod trunk push, GitHub Release

## 6. Dependencies and external blockers

The business prerequisites in PRD §27 gate specific phases, not all code. Submit long-lead items at the start of Phase 0.


| Phase                              | Blocked by                                                                                                                                                               | Lead time                     |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------- |
| Phase 4 (Apple Pay)                | BR-3, BR-4, BR-5 (Merchant ID, payment processing cert, domain verification)                                                                                             | < 1 week (Payabli-controlled) |
| Phase 5 (TTP attestation)          | BR-6 (App Attest production endpoint), BR-21 (backend `/attest` verification)                                                                                            | Backend config                |
| Phase 6 (Fiserv + ProximityReader) | **BR-2 (TTP entitlement, 2–6 week Apple review)**, BR-8, BR-9, BR-10 (Fiserv contract / onboarding / license)                                                            | 4–12 weeks                    |
| Phase 10 (release)                 | BR-1, BR-7, BR-15, BR-16, BR-17, BR-18, BR-19 (Apple Developer Program, distribution cert, CocoaPods trunk, SPM hosting, XCFramework hosting, license, Privacy Manifest) | 1–2 weeks                     |


**Critical path:** Phase 6 has the longest external lead time. The TTP entitlement request (BR-2) must be filed at the start of Phase 0 so it is approved by the time engineering reaches Phase 6.

## 7. Sequencing and critical path

Serialized critical path (if staffing lean):

```
Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 5 → Phase 6 → Phase 10
```

Parallelizable once core is stable:

- Phase 4 (Apple Pay) — after Phase 2
- Phase 7 (Telemetry) — after Phase 1
- Phase 8 (Demo app) — grows incrementally alongside Phases 2–5
- Phase 9 (Cross-platform bridges) — after Phase 3

## 8. Testing strategy

Aligned with PRD §12.

- **Unit tests** (Phases 1–7): validators, ViewModel state, model encoding, state-machine transitions, retry policy bounds, mocked `DCAppAttestService` and `PKPaymentAuthorizationController`
- **Integration tests** (Phases 2, 3, 5): end-to-end flows against `api-sandbox.payabli.com` — tokenization, `getpaid` (approved/declined/validation/server), TTP challenge→register→attest→config→initiate→update, 401 recovery
- **Instrumented tests** (Phase 6): physical iPhone XS+ on iOS 16.7+ against Fiserv sandbox
- **Manual QA** (Phase 8): §12.3 checklist against demo app — form UX, wheel picker, sheet dismissal, Apple Pay on real device, TTP lifecycle, unsupported-device error paths, cross-platform demos
- **TTP test matrix** (§12.4): the 10 scenarios in the PRD are executable against the mock provider (Phase 5) and the Fiserv provider (Phase 6)

## 9. Observability and success metrics

Per PRD §23–§25, the SDK emits telemetry via Phase 7's `TelemetryClient` to power:

- **Adoption & activation** (§23.1): SDK installations, active integrations, TTP activation rate > 95%
- **Transaction success** (§23.2): tokenization > 99%, TTP charge > 97%, TTP end-to-end > 99.5%
- **Reliability** (§23.3): TTP init p95 < 8s, charge p95 < 6s, crash-free sessions > 99.9%
- **Alerting** (§25): critical thresholds page on-call (tokenization < 95%, charge < 90%, crash-free < 99.5%); warnings route to Slack next business day

Dashboards are tiered: Internal (Payabli eng), Partner (integrators), Merchant (in-person operators).

## 10. Security and compliance

Per PRD §6.1 (NFR-1..5G) and §27.3:

- Sensitive data (PAN, CVV, account numbers) **never** touches the host application — captured by SwiftUI `@State` inside the SDK, transmitted directly to Payabli over TLS
- `clientSecret` is only sent to `/api/v2/token/serverside`; never logged, persisted, or forwarded (NFR-5C)
- Fiserv credentials exist only in RAM (NFR-5D)
- Keychain holds only non-secret identity (`keyId`, `deviceId`)
- `os_log` uses `.private` redaction for any potentially sensitive metadata
- Privacy Manifest (`PrivacyInfo.xcprivacy`) declares required-reason APIs and tracking domains (BR-19)
- PCI SAQ-A guidance documentation ships with v1.0 (BR-13)

## 11. Drawbacks

- **Umbrella XCFramework is larger than necessary** for host apps that only want tokenization. §28.11 recommends starting with umbrella and splitting when a second component ships, but this means every v1.0 consumer links the TTP code paths even if they don't use them. Mitigated by Xcode dead-code stripping, but not eliminated.
- **Lockstep versioning** (§28.9) prevents host apps from upgrading one component without upgrading core. Necessary for ABI compatibility across components, but reduces flexibility.
- **Client credentials in-SDK** (v1.0) is weaker than server-minted session JWTs (v2.0 roadmap, §16). Partners must protect `clientSecret` appropriately; the SDK cannot enforce this.
- **Tap to Pay entitlement (BR-2) is a hard external dependency** with 2–6 week Apple review. Delays here block Phase 6.
- **Fiserv is the only v1.0 provider.** The abstraction supports alternatives (FR-11A), but none are implemented. Partners using non-Fiserv processors cannot use Tap to Pay in v1.0.

## 12. Alternatives considered

**Single monolithic module vs component suite.** Rejected. The PRD explicitly architects around Embedded Components V2 (§1, §28). A monolith would force breaking changes when Payout/Reporting/Onboarding ship. Component suite adds upfront cost for long-term flexibility.

**UIKit forms vs SwiftUI.** Rejected. PRD specifies SwiftUI (§7.1). UIKit would need bridging for `ObservableObject` / `@Published` anyway, and SwiftUI is the forward direction for iOS 15+.

**Direct Apple ProximityReader (no Fiserv).** Deferred. Using ProximityReader directly would avoid the Fiserv contract dependency, but Payabli's backend currently routes TTP payments through Fiserv. §15 lists direct ProximityReader as a future consideration once backend support exists.

**Server-minted session JWTs in v1.0.** Deferred. §16 describes the target auth model, but shipping it in v1.0 requires web-platform changes Payabli is not ready to make. The client-credentials flow is pre-positioned for a non-breaking migration (§16.7).

`**@objc` / `NSObject` everywhere vs Swift-native API.** Mixed approach chosen. Public surface uses `@objc NSObject` (FR-6.6) for MAUI and React Native compatibility, but internal types use Swift-native features (actors, `AsyncStream`, value types). This costs some Swift ergonomics at the boundary but makes cross-platform bridging tractable.

## 13. Unresolved questions

1. **Is BR-2 (Tap to Pay entitlement) already filed?** If not, it must be submitted at the start of Phase 0.
2. **Is the Fiserv `FiservTTP` SPM package (≥ 1.0.7) accessible today?** If not, Phase 6 proceeds against a mock `TapToPayProvider` and integrates Fiserv when the SDK becomes available.
3. **Is the Apple Pay Merchant ID + payment processing certificate (BR-3, BR-4) in place for sandbox testing?** Blocks Phase 4 integration tests.
4. **Umbrella XCFramework or per-component XCFrameworks for v1.0?** §28.11 recommends umbrella; confirm before Phase 10.
5. **Is MAUI (and therefore Obj-C binding surface) a day-one requirement?** Affects how aggressively `@objc` is applied in Phases 1–3.
6. **Does any partner need server-minted JWTs on day one?** If so, the v2.0 auth roadmap (§16) moves into v1.0 scope and reshapes the plan.

## 14. Future work

Tracked in PRD §15:

- `PayabliSDKPayout`, `PayabliSDKReporting`, `PayabliSDKOnboarding` components
- Session-JWT auth with Tier 1/Tier 2 state-machine tracking (§16)
- TTP `.auth` / `.refund` / `.void` transaction types
- 3DS challenge flow
- Direct Apple ProximityReader provider (no Fiserv)
- `BGTaskScheduler`-based background queue sync
- Digital receipts, invoice wiring for TTP
- Localization, accessibility audit, React Native example app

## 15. Approval


| Role                   | Name  | Status |
| ---------------------- | ----- | ------ |
| Engineering lead       | *tbd* | —      |
| Product                | *tbd* | —      |
| Security / Compliance  | *tbd* | —      |
| Backend (dependencies) | *tbd* | —      |


