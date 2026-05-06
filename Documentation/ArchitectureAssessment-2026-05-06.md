# Payabli iOS SDK — Architecture Assessment

**Date:** 2026-05-06
**Branch:** `worktree-assessment+swift-library-architecture`
**Baseline:** `swift build` clean on `main` as of commit `180dff6`
**Scope:** Encapsulation and testability for a multi-module Swift library — current state on the TTP-only `main` branch, plus forward-readiness for re-introducing `PayabliSDKPayIn` from `develop` and adding future modules.
**Lens:** The principle being upheld is "components fully self-encapsulated and testable as we add more into the library."

---

## Executive summary

The SDK has the right structural primitives in place: protocol-defined seams at every platform boundary (App Attest, NFC, Keychain, telemetry transport), constructor-injected dependencies on the public facade, and a zero-dependency Core target. Test infrastructure (`StubURLProtocol`, `InMemorySecureStorage`, `MockTapToPayProvider`, `MockAppAttestor`) is rich enough to exercise the SDK end-to-end without touching real hardware or the network.

The structural risk is concentrated in one place: **shared session state is constructed per-component instead of in Core.** `PayabliTTP` builds its own `PayabliAuth` and `PayabliService` at init time, so when `PayabliPayIn` rejoins the package every consumer that uses both modules will hold two unshared auth actors and refresh tokens twice. Several other findings (open-coded 401 retry loops, duplicated HTTP error mapping, retry primitives parked in TapToPay, transport-level boilerplate in each endpoint client) are downstream of the same root cause: there is no canonical Core "session/transport" object that future modules can plug into.

Five high-impact proposals are attached at the end of this document. They are sequenced to land safely on top of `main`, with no public-API breaking change required for any of them — the convenience init that ships today can stay verbatim.

---

## How this assessment was conducted

**Authoritative sources reviewed** (full list in the appendix):

- Swift API Design Guidelines.
- Swift Package Manager documentation, including WWDC19 #410 ("Creating Swift Packages").
- Library Evolution / resilient-frameworks guidance (`swift.org/blog/library-evolution`).
- SE-0386 (`package` access modifier).
- Underscored attributes reference (`@_spi`, `@_implementationOnly`).
- Swift 6 Concurrency Migration Guide and the server-side concurrency-adoption guide for library authors.
- Swift DocC documentation guide.

**Reference Swift libraries surveyed for real-world conventions:**

`apple/swift-collections`, `apple/swift-nio`, `apple/swift-log`, `apple/swift-argument-parser`, `vapor/vapor`, `Alamofire/Alamofire` — Package.swift, top-level `Sources/` layout, public-vs-internal split, and test-target organization.

**Codebase audit method:**

Read `Package.swift`, `CLAUDE.md`, and the highest-leverage source files in each module (entry-point facades, protocols defining seams, the auth/transport/error layer in Core, the attestation/retry/secure-storage layer in TapToPay). Spot-checked internal coupling by searching `import` patterns and `@testable` usage. Findings reference repo-relative file paths and line numbers.

---

## Strengths to preserve as the library grows

1. **Seam-first design at every platform boundary.** `AppAttestor`, `DeviceAttestationService`, `SecureStorage`, `TapToPayProvider`, and `TelemetryTransport` are all protocols, with concrete adapters (`RealAppAttestor`, `KeychainStorage`, `FiservCardReader`, `URLSessionTelemetryTransport`) attached at construction time. Every test fake (`MockAppAttestor`, `MockTapToPayProvider`, `MockDeviceAttestationService`, `InMemorySecureStorage`, `InMemoryTelemetryTransport`) substitutes cleanly without `@testable` privileges.

2. **Constructor injection on the facade.** `PayabliTTP`'s designated init takes `provider`, `attestation`, `retryPolicy`, and `URLSession` directly. Every dangerous global is swappable; the test target proves it. This is exactly the Alamofire `Session(configuration:delegate:rootQueue:...)` pattern and the NIO "pass everything in" pattern.

3. **Module-level zero-dep discipline.** `PayabliSDKCore` has no third-party imports; `sentry-cocoa` and `posthog-ios` are not in the SPM graph at all. The `TelemetryTransport` protocol pattern keeps vendor SDKs in the host application. `PayabliCardReaderCore` is platform-gated via `condition: .when(platforms: [.iOS])` so cross-platform CI compiles cleanly — this is the same conditional-compilation pattern Apple recommends for SPM libraries.

4. **`@testable import` is structurally unnecessary for most tests.** Mocks live alongside protocols, the facade is fully constructor-injectable, and the wire layer is testable via `StubURLProtocol`. Tests that *do* reach for `@testable` (Finding 16) are doing so reflexively, not because the design forces them to.

These four properties are the foundation. The recommendations below build on them rather than redesigning around them.

---

## Top forward-readiness risks

Three risks dominate the "add more components" trajectory. Each is anchored to specific findings below.

1. **Auth/HTTP coupling will duplicate when PayIn re-lands.** `PayabliTTP` instantiates its own `PayabliService` and `PayabliAuth` per construction. When `PayabliPayIn` returns from `develop`, two facades on the same config will refresh tokens twice and one's 401-recovery won't update the other's cached token. CLAUDE.md and PRD §28.8 state that components share the underlying auth session, but the code does not enforce or implement this. (**Finding 1**, downstream **Findings 5, 6, 13**.)

2. **Networking primitives are TapToPay-shaped, not module-shaped.** `PayabliEnvelope` lives in Core, but `RetryPolicy`, `Retry`, `EventMulticaster`, and the per-request 401-refresh loop live in TapToPay. Every new component will copy these or reach across modules. (**Findings 3, 4, 6**.)

3. **`PayabliService` is a `final class`, not a protocol — there is no transport seam.** `TTPConfigClient` and `TTPTransactionClient` depend on the concrete type, so there is no place to insert request-time middleware (assertion headers, auth-bearer attachment, telemetry on every request, signed-request envelopes). Each new endpoint client copies the boilerplate. (**Finding 5**, enables **Findings 6, 12, 13**.)

The five proposals at the end of this document neutralize all three risks together.

---

## Findings

19 findings, ranked by severity. Each cites a specific file path and symbol or line range.

### Critical

#### Finding 1 — `PayabliAuth` is constructed per-component instead of shared via Core

**Location:** `Sources/PayabliSDKTapToPay/PayabliTTP.swift:136-141`

**Observation:** `PayabliTTP.init(config:appId:provider:attestation:...)` constructs a fresh `PayabliService` and a fresh `PayabliAuth` actor every time. There is no Core-level "session registry" that vends a single `PayabliAuth` for a given `PayabliConfig`. CLAUDE.md and PRD §28.8 state that components share the underlying auth session, but the code does not enforce or implement this. When PayIn returns from `develop`, two facades on the same config will refresh tokens twice and one's 401-recovery won't update the other's cached token.

**Why it matters:** Encapsulation gap and forward-readiness gap. Every new module repeats this pattern, and bugs surface only when two modules are used together — exactly the regime the SDK is heading into.

**Recommendation:** Introduce `PayabliSession` (Core, public) that owns one `PayabliAuth` + one `PayabliService` per `PayabliConfig`. Components accept a `PayabliSession`, not a raw `PayabliConfig`. Convenience inits stay; they build a session internally. See **Proposal A** for the full plan.

---

### Major

#### Finding 2 — `PayabliConfig` is `final class @unchecked Sendable` with only let properties

**Location:** `Sources/PayabliSDKCore/Public/PayabliConfig.swift:34-68`

**Observation:** `PayabliConfig` is a class (not struct) with `@unchecked Sendable` plus only `let` properties. Class identity adds nothing — there is no inheritance, no shared mutable state, no need for reference semantics. The `@unchecked` opt-out hides the fact that `PayabliTokenRefresh` is already `@Sendable`, which means a `struct` would be `Sendable` automatically.

**Why it matters:** Encapsulation. As more components share configuration, value semantics make config diffing and "is this the same session?" comparisons trivial; reference semantics force callers to track identity explicitly. Mature Swift libraries (swift-log `Logger`, swift-collections everything) default to value types for shared configuration.

**Recommendation:** Convert to `public struct PayabliConfig: Sendable` and drop `@unchecked`. Audit call sites for unintended `===` comparisons. Once Proposal A lands, `PayabliSession` becomes the identity-bearing object; `PayabliConfig` can safely be a value.

---

#### Finding 3 — `RetryPolicy` and `Retry` live in TapToPay but are component-agnostic

**Location:** `Sources/PayabliSDKTapToPay/RetryPolicy.swift:1-94`

**Observation:** `RetryPolicy` (the data), `Retry.run` (the runner), and `RetryableError` are generic over the operation. They have no TapToPay-specific dependency except `PayabliTTPError.updateFailed` as a fallback throw. PayIn will need the same pattern for tokenize-with-retry, getpaid-with-retry, and so on — copy/paste is the path of least resistance.

**Why it matters:** Forward-readiness. Each new module re-implementing exponential backoff with jitter is duplication and a divergence risk. Subtle differences in retryable status codes between modules surface as field bugs.

**Recommendation:** Move `RetryPolicy`, `Retry`, and `RetryableError` to `Sources/PayabliSDKCore/Networking/`. Replace the TapToPay-specific fallback `PayabliTTPError.updateFailed(reason: "Exhausted retries")` with `PayabliGenericError(code: .networkError, ...)` so the Core type knows nothing about TapToPay.

---

#### Finding 5 — `PayabliService` is a `final class` — there is no transport seam

**Location:** `Sources/PayabliSDKCore/Networking/PayabliService.swift:17`, plus consumers `Sources/PayabliSDKTapToPay/TTPConfigClient.swift:18-32` and `Sources/PayabliSDKTapToPay/TTPTransactionClient.swift:9-17`.

**Observation:** Every endpoint client takes the concrete `PayabliService`. Tests substitute via `StubURLProtocol` — fine for HTTP-level integration tests, but it means there is no seam to insert request-time middleware. Right now `TTPConfigClient` hand-merges `Authorization` and `X-App-Assertion` into the request dict (`TTPConfigClient.swift:42-50`); `TTPTransactionClient.initiate` does the same (`TTPTransactionClient.swift:34,48`). Each new client repeats the boilerplate.

**Why it matters:** Encapsulation + forward-readiness. A v2 module that needs a different auth scheme or a global "attach idempotency-key" middleware has nowhere to plug in.

**Recommendation:** Extract `protocol PayabliTransport: Sendable { func perform(_:) async throws -> PayabliResponse; func performV2<T>(_:decoding:) async throws -> PayabliV2Envelope<T> }`, conform `PayabliService` to it, and have `TTPConfigClient` and `TTPTransactionClient` depend on the protocol. Add an internal `AuthenticatedTransport` decorator that injects the bearer header automatically. See **Proposal B**.

---

#### Finding 6 — 401-refresh-and-retry is open-coded in `PayabliTTP+Charge.tryUpdate`

**Location:** `Sources/PayabliSDKTapToPay/PayabliTTP+Charge.swift:177-235`

**Observation:** The 401 → `auth.invalidateAndRefresh()` → retry-once dance is a 50-line inline closure inside `tryUpdate`. `TTPConfigClient.fetchConfig` (`TTPConfigClient.swift:64-66`) handles 401 differently — it throws `.tokenExpired` and lets the facade clear attestation. There is no canonical place where "transport-level 401 means try refresh once" lives. PayIn's tokenize/getpaid endpoints will need the same dance.

**Why it matters:** Encapsulation + forward-readiness; subtle divergence between modules guaranteed.

**Recommendation:** Bake the 401-retry policy into the `AuthenticatedTransport` decorator from Proposal B. Endpoint clients become straight-line.

---

#### Finding 7 — `TapToPayProviderFactory.shared` is a public mutable singleton, and the convenience init bypasses it

**Location:** `Sources/PayabliSDKTapToPay/TapToPayProviderFactory.swift:9-39`

**Observation:** `TapToPayProviderFactory` is a class-typed `@unchecked Sendable` singleton with a public `register` and a private-init plus a public `.shared`. Tests reset state via `resetForTesting()`. Worse: it is never called by `PayabliTTP` — the convenience init wires `FiservCardReader()` directly (`PayabliTTP.swift:112`). So the factory exists but is not on the production path; it is a singleton with public registration, no enforced ownership, no lifecycle, and no consumer.

**Why it matters:** Encapsulation. Mutable global state in a payments SDK is risky; if a host app calls `register` from two threads or two modules, behavior is order-dependent. Mature Swift libraries deliberately avoid mutable public globals (Alamofire's `AF` is just a default `Session` instance you can replace; swift-log forbids configuration after `LoggingSystem.bootstrap`).

**Recommendation:** Either (a) make `TapToPayProviderFactory` a value type owned by each `PayabliTTP` instance (instance state, not global), or (b) delete it until it has a real consumer. If kept, make `.shared` `internal`. See **Proposal D**.

---

### Minor

#### Finding 4 — `EventMulticaster` is a generic primitive parked in TapToPay

**Location:** `Sources/PayabliSDKTapToPay/EventMulticaster.swift:1-63`

**Observation:** `EventMulticaster` is hard-coded to `AsyncStream<PayabliTTPEvent>`, but the implementation is purely structural. PayIn's eventual `events()` stream and Telemetry's flush hooks would benefit from a shared generic implementation.

**Recommendation:** Generalize to `public final class EventMulticaster<Event: Sendable>` and move to Core. TapToPay aliases `typealias TTPMulticaster = EventMulticaster<PayabliTTPEvent>`.

#### Finding 8 — `PayabliTTP` ivars are module-internal but readable from any extension

**Location:** `Sources/PayabliSDKTapToPay/PayabliTTP.swift:42-62`

**Observation:** `entryPoint`, `appId`, `service`, `auth`, `transactionClient`, `configClient`, `cachedDeviceId`, `sessionManager`, `multicaster`, `retryPolicy` are all `internal` (the absence of `private`). This is an intentional consequence of splitting across `+Initialize`, `+Charge`, `+Activation` files, and CLAUDE.md justifies it. It also means any future file in the module can mutate `cachedDeviceId` or call `multicaster.emit` directly, defeating state-machine invariants in `SessionManager`.

**Recommendation:** Acceptable today. Revisit if more files join the module. Long-term, consider Swift 5.9+ `package` access for cross-file-but-not-module sharing, or wrap these in a single `private` ivars struct accessed via methods.

#### Finding 9 — `SessionManager` is `public` but its mutators are `internal`

**Location:** `Sources/PayabliSDKTapToPay/SessionManager.swift:10-46`

**Observation:** `SessionManager` is `public final class ObservableObject` exposing `@Published public private(set) var sessionState`. Its mutators (`transition`, `forceSessionExpiry`, `markError`, `reset`) are `internal`. Yet `PayabliTTP` already publishes `sessionState`/`isReady` (`PayabliTTP.swift:69-70`), so the public exposure of `SessionManager` duplicates the surface — and host apps that grab the inner `SessionManager` could observe transitions the facade has not synced yet.

**Recommendation:** Make `SessionManager` `internal`. There is no consumer use case for instantiating or observing it directly.

#### Finding 10 — `AppAttestService` exposes hardware-identifier providers as public init parameters

**Location:** `Sources/PayabliSDKTapToPay/AppAttestService.swift:31-63`

**Observation:** `AppAttestService` is `public final class @unchecked Sendable` with a public init taking four `@Sendable () -> String` providers. The reason ("so tests on macOS can substitute deterministic values") is fair, but the testing seam is on the production class signature. This is a public API surface expansion driven by test ergonomics.

**Recommendation:** Keep one public init `(service:auth:attestor:storage:)` and move the hardware-id providers behind an internal init or a single `HardwareIdentityProvider` protocol with a default implementation. Tests inject the protocol; consumers see one initializer.

#### Finding 11 — `FiservCardReader.Credentials` and `setCredentials` are public on the adapter

**Location:** `Sources/PayabliSDKTapToPay/Adapters/FiservCardReader.swift:25-77`

**Observation:** The Fiserv credentials struct and `setCredentials(_:)` are `public`. Per `TapToPayProvider`, the facade flows the raw `[String: String]` from `/config` and the adapter parses it. There is no consumer pathway where a host should construct `FiservCardReader.Credentials` directly — doing so would bypass NFR-5D ("credentials live in RAM only, never persisted across sessions") because the host would have to store them somewhere.

**Recommendation:** Make `Credentials` and `setCredentials` `internal`. Tests already use `@testable import`.

#### Finding 12 — TTP error mapping for HTTP status codes is duplicated between `PayabliService.mapHTTPError` and `TTPConfigClient.fetchConfig`

**Location:** `Sources/PayabliSDKCore/Networking/PayabliService.swift:127-166` vs. `Sources/PayabliSDKTapToPay/TTPConfigClient.swift:64-87`

**Observation:** `PayabliService.mapHTTPError` is the canonical 4xx/5xx → `PayabliError` mapper. `TTPConfigClient` handles status codes manually (401 → `.tokenExpired`, 403 → `.devicePendingActivation`) without going through it. Adding a new module today would naturally write its own 401/403/404 handling; subtle behavioral drift will follow.

**Recommendation:** Extend `mapHTTPError` to support component-specific overrides via a `mapping: (Int) -> PayabliError?` closure, then call it from every endpoint client. Lands naturally on top of Proposal B.

#### Finding 13 — `PayabliConfig.tokenProvider` is the only refresh seam — no way to react to token rotation

**Location:** `Sources/PayabliSDKCore/Auth/PayabliAuth.swift:28-64`

**Observation:** When `PayabliAuth` refreshes the token, no observer is notified. A second component instance (when PayIn lands) holding a stale `currentToken` would not know that a sibling refreshed. Today this is masked because each component holds its own `PayabliAuth`, but combined with Finding 1 (sharing the actor), an `AsyncStream<TokenChange>` or a `didRefresh` closure would let downstream subscribers react.

**Recommendation:** Once `PayabliSession` (Proposal A) exists, add `var tokenChanges: AsyncStream<String> { get }` to `PayabliAuth` so the eventual telemetry/logging/header pipelines can observe rotations.

#### Finding 14 — Umbrella `PayabliSDK` library aggregates Core + TapToPay but does not include Telemetry; no codified rule

**Location:** `Package.swift:34-38`

**Observation:** The umbrella `.library(name: "PayabliSDK", targets: ["PayabliSDKCore", "PayabliSDKTapToPay"])` excludes `PayabliSDKTelemetry`. CLAUDE.md notes "ships Core + TapToPay + CardReaderCore" intentionally, but the rule for what goes in the umbrella vs. what stays optional is not codified. Each new module becomes a discretionary call.

**Recommendation:** Add a one-line rule to CLAUDE.md (suggested: "any module on the critical-path of an ICA-required flow"). Telemetry stays out; PayIn comes in.

#### Finding 15 — `SessionTierValidator` is a stub but ships as `public` API

**Location:** `Sources/PayabliSDKCore/Auth/SessionTierValidator.swift:15-42`

**Observation:** `detectedTier(from:)` always returns `.tier1Transactional`. The function body comment acknowledges "v2.0 JWT adoption will flesh this out". Shipping a public function whose only behavior is "return a constant" commits us to a signature that may not survive that v2.0 change.

**Recommendation:** Make `SessionTierValidator` `internal` until tier detection is real. Components that need tier-gating call into Core via a non-public seam.

#### Finding 16 — TapToPay test target uses `@testable import` reflexively for trivially-public types

**Location:** Every file under `Tests/PayabliSDKTapToPayTests/`

**Observation:** Most TapToPay tests use `@testable import PayabliSDKTapToPay` even though they only touch public types. The few that genuinely need internal access are `TapToPayProviderFactoryTests` (calls internal `resetForTesting`), and a handful of attestor-companion tests. When everything is `@testable`, the SDK can no longer tell which internals are load-bearing for tests.

**Recommendation:** Audit each test file and downgrade to plain `import` where possible. Reserve `@testable` for the few cases that genuinely need it.

#### Finding 17 — `PayabliTTP` is `@MainActor`-isolated end to end, even for non-UI components

**Location:** `Sources/PayabliSDKTapToPay/PayabliTTP.swift:38`

**Observation:** Slapping `@MainActor` on the entire facade is defensible for SwiftUI consumption (it owns `@Published` state). It also means non-UI components like `transactionClient` and `multicaster` are captured in main-actor isolation when accessed via the facade, and every test method must be `@MainActor`. As more module facades land, the pattern of "everything `@MainActor`" will spread.

**Recommendation:** Consider isolating only the `@Published` surface to `@MainActor` (a small `MainActor`-isolated `ObservableObject` viewmodel) and keeping the facade actor-agnostic. Defer; this is a refactor, not a bug.

#### Finding 18 — `PayabliCardReaderCore` import surface leaks `import ProximityReader` into the adapter

**Location:** `Sources/PayabliSDKTapToPay/Adapters/FiservCardReader.swift:5`

**Observation:** The adapter does `import ProximityReader` directly under `canImport(PayabliCardReaderCore)`. Since `PayabliCardReaderCore` already re-exports `ProximityReader` symbols transitively, this import is redundant and means the adapter has independent knowledge of Apple's framework name.

**Recommendation:** Drop `import ProximityReader` from the adapter — let `PayabliCardReaderCore` own the framework dependency. Verify with `swift build`.

#### Finding 19 — Minor housekeeping (rolled up)

- `PayabliEnvironment.local = "https://wallets-test.ngrok.app"` (`Sources/PayabliSDKCore/Public/PayabliEnvironment.swift:18`) — a developer-specific ngrok URL ships in the public enum. Remove before public release or hide behind `#if DEBUG`.
- `PayabliService.makeDefaultSession()` is `private static` and untestable; lift to `internal` so the test target can verify configuration.
- `PayabliValidationError.code` returns `.decodingError` (`Sources/PayabliSDKCore/Models/PayabliError.swift:76`) — semantically wrong; should map to a new `.validation` case or `.unknown`. `PayabliErrorCode` enum has no `.validation` case despite being the primary 400 mapping.
- `Locked<Value>` and `UncheckedSendableBox<Value>` (`Sources/PayabliSDKTapToPay/PayabliTTP.swift:286-310`) — module-level `internal` types that exist only for the ObjC bridge. Move to a `_ObjCBridging.swift` file so the facade is not bloated.
- `KeychainStorage` is `public struct` with `data(forKey:)`/`set(_ data:)` overloads that no consumer needs. Trim public surface to the `SecureStorage` protocol.
- `PayabliCore`/`PayabliTapToPayModule` namespace enums each expose a hard-coded `version = "1.0.0"` string. As releases multiply, this drifts from git tags. Generate at build time or read from `Bundle.main.infoDictionary`.

---

## Decision-ready proposals

Five high-impact proposals. They are ordered for safe, dependency-respecting sequencing: A enables B, B enables C, D and E are independent.

None of these proposals require a public-API breaking change. The convenience init exposed in `README.md` continues to work verbatim throughout.

---

### Proposal A — Introduce `PayabliSession` in Core

**Resolves:** Finding 1 (critical). Partially Finding 2. Enables Finding 13.
**Effort:** ~1 day; bulk is the test-fixture refactor.
**Risk:** Low. No public-API break.

**Goal:** A single `PayabliAuth` + `PayabliService` per `PayabliConfig`, owned by Core, shared by every component facade.

**Steps:**

1. Create `Sources/PayabliSDKCore/Public/PayabliSession.swift`:

   ```swift
   public final class PayabliSession: @unchecked Sendable {
       public let config: PayabliConfig
       internal let auth: PayabliAuth
       internal let service: PayabliService

       public init(config: PayabliConfig, urlSession: URLSession? = nil) {
           self.config = config
           self.auth = PayabliAuth(...)
           self.service = PayabliService(auth: auth, urlSession: urlSession ?? .makeDefault())
       }
   }
   ```

   `auth` and `service` are `internal` so consumers don't reach in directly; they go through Core's transport.

2. In TapToPay, add a new designated init `PayabliTTP.init(session:appId:provider:attestation:retryPolicy:)`. The existing `init(config:appId:...)` becomes a thin convenience that builds a `PayabliSession` and delegates.

3. The public consumer-facing init (`init(accessToken:tokenProvider:entryPoint:appId:environment:)`) is unchanged. Internally it now builds a `PayabliConfig`, then a `PayabliSession`, then calls the new designated init.

4. Update `PayabliTTPTests.makeTTP` to construct one `PayabliSession` and pass it to all helpers in the same test. The mocks do not change.

5. When PayIn re-lands, its facade also takes `session:` — sharing is structural rather than enforced through documentation.

**Migration path for consumers:** None. Public surface is unchanged.

**Open questions:**

- Should `PayabliSession` cache by `PayabliConfig` value-equality so two host-app constructions reuse the same actor? Default: no (object identity is the contract). Revisit if multi-instance usage emerges.
- Should the `service` be promoted to `public` on the session so host apps could (in theory) make raw calls? Recommendation: no — keep it `internal`. Hosts that need raw calls have a specific use case worth designing against.

---

### Proposal B — Promote `PayabliTransport` protocol with `AuthenticatedTransport` decorator

**Resolves:** Findings 5 and 6. Enables Finding 12.
**Effort:** ~1.5 days. Most of the time is sweeping endpoint clients onto the protocol.
**Risk:** Low. Internal change; no public-API impact.

**Goal:** Endpoint clients depend on `protocol PayabliTransport`, not concrete `PayabliService`. Auth-bearer attachment and 401-refresh-once become a single decorator that every module uses.

**Steps:**

1. Define the protocol in Core, `Sources/PayabliSDKCore/Networking/PayabliTransport.swift`:

   ```swift
   public protocol PayabliTransport: Sendable {
       func perform(_ request: PayabliRequest) async throws -> PayabliResponse
       func performV2<T: Decodable>(_ request: PayabliRequest, decoding: T.Type) async throws -> PayabliV2Envelope<T>
   }
   ```

2. Conform `PayabliService` to `PayabliTransport`.

3. Add `internal struct AuthenticatedTransport: PayabliTransport` in Core that wraps another `PayabliTransport` and:
   - Injects the `Authorization: Bearer <token>` header from `PayabliAuth`.
   - On 401, calls `auth.invalidateAndRefresh()` and retries once. After two consecutive 401s, throws `PayabliError.tokenExpired`.

4. `PayabliSession.transport: PayabliTransport` returns an `AuthenticatedTransport` wrapping its `service`. Endpoint clients (`TTPConfigClient`, `TTPTransactionClient`) take `transport: PayabliTransport` instead of `service: PayabliService`.

5. Delete the open-coded 401 loop in `PayabliTTP+Charge.tryUpdate`. The endpoint call becomes a single line.

6. The `X-App-Assertion` header in `TTPConfigClient` is component-specific, not a transport concern — leave it inline. Generic transport-level headers (auth, idempotency-key, telemetry) live in decorators stacked on top.

**Migration path:** Internal only. No host changes.

**Risks:** The retry-once policy was implicit before; making it explicit means double-checking that no existing call site relied on the 401 propagating without a refresh. Spot-check: `TTPConfigClient.fetchConfig` deliberately throws `.tokenExpired` on 401 to let the facade clear attestation; that semantics must be preserved (the decorator throws after the retry fails).

---

### Proposal C — Move retry primitives and `EventMulticaster` to Core

**Resolves:** Findings 3 and 4.
**Effort:** ~2 hours; pure file move + import cleanup.
**Risk:** Trivial. No public-API impact (these types are not in the public surface today).

**Goal:** Core hosts every primitive that future modules will reuse.

**Steps:**

1. Move `Sources/PayabliSDKTapToPay/RetryPolicy.swift` → `Sources/PayabliSDKCore/Networking/RetryPolicy.swift`. Replace the `PayabliTTPError.updateFailed(reason: "Exhausted retries")` fallback in `Retry.run` with `PayabliGenericError(code: .networkError, message: "Exhausted retries")`. Core knows nothing about TapToPay.

2. Generalize `Sources/PayabliSDKTapToPay/EventMulticaster.swift` to `public final class EventMulticaster<Event: Sendable>` and move it to `Sources/PayabliSDKCore/Concurrency/EventMulticaster.swift`. TapToPay adds `internal typealias TTPMulticaster = EventMulticaster<PayabliTTPEvent>`.

3. Update imports in TapToPay. Run `swift build` and the test suite to confirm no regression.

**Migration path:** Internal only.

---

### Proposal D — Demote `TapToPayProviderFactory` to instance state, or delete

**Resolves:** Finding 7.
**Effort:** ~30 min for either path.
**Risk:** Low. The factory is not on the production hot path.

**Goal:** No public mutable singleton in the module surface.

**Two options. Recommendation: option (b).**

**(a)** Make `TapToPayProviderFactory` an instance type owned by each `PayabliTTP`. Move `register` to a typed configuration on `PayabliTTP.init`. Keep `.shared` reference counted with `internal` access.

**(b)** **Delete `TapToPayProviderFactory` entirely.** It has no production caller. Tests can substitute `provider:` directly via the existing `PayabliTTP` designated init. The class exists for a future "multiple registered providers, pick by name" use case that has not materialized; reintroduce it when there is a real second provider, with the design informed by the actual second-provider requirements.

**Recommendation: (b).** Delete now, reintroduce later if needed. YAGNI, and removing dead public surface is always cheaper than evolving it.

**Migration path:** None. The convenience init that ships today wires `FiservCardReader()` directly; deleting the factory has zero behavioural impact.

---

### Proposal E — Ship a `PayabliSDKTestUtils` library product

**Resolves:** Strengths preservation (forward-looking; not anchored to a single finding).
**Effort:** ~1 day. Mostly file relocation and a small public-API design pass on the fixtures.
**Risk:** Low. Adds a target; subtracts nothing.

**Goal:** Test fixtures (`InMemorySecureStorage`, `MockAppAttestor`, `MockTapToPayProvider`, `MockDeviceAttestationService`, `StubURLProtocol`, `InMemoryTelemetryTransport`) ship as a real SPM library product. Host-app integration tests can depend on them. Future modules' tests can depend on them.

This is exactly the pattern Apple uses: NIO ships `NIOEmbedded` and `NIOTestUtils` as products; `swift-log` ships `InMemoryLogging`; `swift-argument-parser` ships `ArgumentParserTestHelpers`. Today's Payabli SDK has the fixtures but they are buried in `Tests/`, where neither host apps nor sibling modules can reach them.

**Steps:**

1. Create `Sources/PayabliSDKTestUtils/` and move:
   - `Tests/PayabliSDKCoreTests/StubURLProtocol.swift` → `Sources/PayabliSDKTestUtils/StubURLProtocol.swift`
   - `Tests/PayabliSDKTapToPayTests/MockAppAttestor.swift` → `Sources/PayabliSDKTestUtils/MockAppAttestor.swift`
   - `Tests/PayabliSDKTapToPayTests/MockTapToPayProvider.swift` → `Sources/PayabliSDKTestUtils/MockTapToPayProvider.swift`
   - `Tests/PayabliSDKTapToPayTests/MockDeviceAttestationService.swift` → `Sources/PayabliSDKTestUtils/MockDeviceAttestationService.swift`
   - `Tests/PayabliSDKCoreTests/InMemorySecureStorage.swift` → `Sources/PayabliSDKTestUtils/InMemorySecureStorage.swift`
   - `Tests/PayabliSDKTelemetryTests/InMemoryTelemetryTransport.swift` → `Sources/PayabliSDKTestUtils/InMemoryTelemetryTransport.swift`

2. Add to `Package.swift`:

   ```swift
   .library(name: "PayabliSDKTestUtils", targets: ["PayabliSDKTestUtils"]),
   .target(
       name: "PayabliSDKTestUtils",
       dependencies: ["PayabliSDKCore", "PayabliSDKTapToPay"]
   ),
   ```

3. Make each fixture's public surface deliberate. Today they are `internal` because they live in test bundles. Now they are `public` — pick the minimum surface needed by external consumers (this is often smaller than the test-bundle version). Initializers, key methods, and verification hooks (e.g., `recordedRequests`) become `public`; everything else stays `internal`.

4. Update test target dependencies to `["PayabliSDKCore", "PayabliSDKTapToPay", "PayabliSDKTestUtils"]`. Drop `@testable import` where the fixture was the only reason for it.

**Migration path:** None for consumers. Internal test target dependencies update.

**Why this matters now, not later:** Once host apps write tests against the SDK, they will copy/paste these fixtures. Shipping them as a product means there is one canonical implementation, versioned with the rest of the SDK.

---

## Recommended sequencing

1. **Proposal C** first (1-2 hours, trivial). Establishes Core as the home for cross-module primitives. No dependencies on other proposals.
2. **Proposal A** (`PayabliSession`). Lays the foundation for Proposal B. Test-only refactor, no host impact.
3. **Proposal B** (`PayabliTransport`). Deletes the open-coded 401 retry and the per-client header boilerplate.
4. **Proposal D** (delete `TapToPayProviderFactory`). Independent of A/B/C; can land any time. 30 min.
5. **Proposal E** (`PayabliSDKTestUtils`). Independent. Lands once the team is ready to commit to a public test-utils surface.

Findings 8, 14, 17, 19 (minor cleanup, doc updates, deferred decisions) should be addressed in passing during the work above. Finding 15 (`SessionTierValidator` → internal) is a one-character access-modifier change and can land anywhere.

---

## Out of scope

Topics that might be relevant to a future audit but were intentionally out of scope here:

- **DocC coverage of the public API.** Apple's recommendation is a `///` doc comment for every public declaration; a future audit pass could measure this and identify gaps.
- **Sendable / strict-concurrency hardening.** The codebase compiles under Swift 6.3.1 without overrides, but a Complete strict-concurrency audit would surface implicit isolation gaps before they become source-breaking.
- **Library Evolution / `-enable-library-evolution`.** Not turned on in `Package.swift` today; appropriate to defer until the public surface is stable. When the team is ready to ship XCFrameworks with binary stability, this becomes a separate workstream.
- **SemVer hygiene of the public surface.** Now that tags and releases have been cleaned up (per the recent cleanup), the next release will set the floor; a release-readiness checklist (Sendable audit, `@MainActor` audit, public-init audit, doc-comment audit) should gate the first re-tagged release.
- **Bridges (`Bridges/Flutter`, `Bridges/MAUI`, `Bridges/ReactNative`).** Not part of the Swift package graph; assessed separately.
- **`PayabliCardReaderCore`** (vendored MIT). Not modified; contract is byte-for-byte upstream from `Fiserv/TTPPackage`.

---

## Appendix — Sources

**Apple authoritative guidance:**

- Swift API Design Guidelines — https://www.swift.org/documentation/api-design-guidelines/
- Library Evolution in Swift (swift.org blog) — https://www.swift.org/blog/library-evolution/
- SE-0386 (`package` access modifier) — https://github.com/swiftlang/swift-evolution/blob/main/proposals/0386-package-access-modifier.md
- Swift Underscored Attributes Reference (`@_spi`) — https://github.com/swiftlang/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md
- WWDC19 #410 — Creating Swift Packages — https://developer.apple.com/videos/play/wwdc2019/410/
- Swift 6 Concurrency Migration Guide — https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/migrationstrategy/
- Swift Concurrency Adoption Guidelines for Library Authors — https://www.swift.org/documentation/server/guides/libraries/concurrency-adoption-guidelines.html
- Swift DocC documentation — https://www.swift.org/documentation/docc/

**Reference Swift libraries surveyed:**

- apple/swift-collections — https://github.com/apple/swift-collections
- apple/swift-nio — https://github.com/apple/swift-nio
- apple/swift-log — https://github.com/apple/swift-log
- apple/swift-argument-parser — https://github.com/apple/swift-argument-parser
- vapor/vapor — https://github.com/vapor/vapor
- Alamofire/Alamofire — https://github.com/Alamofire/Alamofire
