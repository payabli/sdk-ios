# PayabliSDKTapToPay

Everything the SDK needs to run a Tap-to-Pay-on-iPhone charge lives in this
module: the public facade, the 9-state session lifecycle, device
attestation, the backend clients, and the processor-agnostic adapter
contract.

> Layout note: this module was promoted from
> `Sources/PayabliSDKPayIn/TapToPay/` to its own SPM target so consumers can
> link Tap to Pay independently of `PayabliSDKPayIn`. PayIn no longer
> depends on `PayabliCardReaderCore`; the TTP transitive dependency lives
> only here.

The module is flat by design — PRD §7.2 fixes the layout and forbids
sub-folders for the TapToPay module (except `Adapters/`, which is the one
sub-folder the PRD does allow). To keep it scalable we rely on three
conventions instead of folders: naming prefixes, companion files, and one
principal type per file.

---

## 1. File groups

Files cluster by concern. Prefixes tell you what concern at a glance.

### Facade — `PayabliTTP*`

The public entry point that host apps consume. Split across companion files
(PRD §7.2 allows companion files in the same folder):

| File | Responsibility |
|---|---|
| `PayabliTTP.swift` | Class declaration, stored properties, init, `events()`, `syncPublished()` |
| `PayabliTTP+Initialize.swift` | `initialize()` (cold/warm path) and `reinitializeIfNeeded()` (fresh `/config` after 401) |
| `PayabliTTP+Activation.swift` | `activateDevice()` for pending-device flows. Emits `activationStarted` / `activationCompleted` / `activationFailed`. The partner provisions the activation code out-of-band (PRD §9.7) |
| `PayabliTTP+Charge.swift` | 3-step sale pipeline: `/initiate` → `startReading` → `/update` (PRD §19.1) |
| `PayabliTTPEvent.swift` | `PayabliTTPEvent` (lifecycle cases) + `PayabliTTPError` (PRD §20) + `PayabliTTPEventCode` (`@objc`) + per-case `payload` schema + `CustomNSError` bridging |
| `PayabliTTPTypes.swift` | `PayabliTTPSessionState`, `PayabliTTPPaymentType`, `TransactionResult` |
| `PayabliTTPTransactionData.swift` | `PayabliTTPCustomerData`, `PayabliTTPPaymentDetails`, `PayabliTTPInvoiceData`, internal `TTPTransactionContext` |
| `PayabliTTPTransactionData+ObjC.swift` | `@objc` companion classes (`PayabliTTPCustomerDataObjC`, `PayabliTTPPaymentDetailsObjC`, `PayabliTTPInvoiceDataObjC`, `PayabliTTPTransactionResultObjC`) used by ObjC / MAUI / Flutter / RN consumers |

---

## 1.5. ObjC interop (bilingual contract)

`PayabliSDKTapToPay` is bilingual Swift/ObjC, following the
[URLSession](https://developer.apple.com/documentation/foundation/urlsession)
and [Stripe Terminal](https://stripe.com/docs/terminal) patterns. Every
Swift `async throws` method has a callback-based `@objc` companion in the
same file; structs have `*ObjC` companion classes; events expose a
`PayabliTTPEventCode` int + `[String: Any]` payload alongside the
associated-value enum; errors bridge cleanly to `NSError` with domain
`"com.payabli.ttp"` and stable per-case codes.

This unblocks the MAUI/Xamarin binding (sharpie consumes the generated
ObjC header), the Flutter `MethodChannel` plugin, and the React Native
`Native Module` — none of which can express Swift `async`, `AsyncStream`,
or value-typed `enum`s with associated values.

| Swift API (unchanged) | ObjC / MAUI / RN companion |
|---|---|
| `try await ttp.initialize()` | `[ttp initializeWithCompletion:^(NSError *err){...}]` |
| `try await ttp.charge(type:paymentDetails:customer:invoice:orderDescription:)` | `[ttp chargeWithType:paymentDetails:customer:invoice:orderDescription:completion:]` returning `PayabliTTPTransactionResultObjC*` + `NSError*` |
| `try await ttp.activateDevice(activationCode:)` | `[ttp activateDeviceWithActivationCode:completion:]` |
| `for await event in ttp.events()` | `[ttp addEventListenerWithHandler:^(PayabliTTPEventCode code, NSDictionary *payload){...}]` returning a `PayabliTTPEventToken` (call `[token cancel]` to stop) |
| `PayabliTTPCustomerData(...)` (struct) | `[[PayabliTTPCustomerDataObjC alloc] initWithFirstName:lastName:customerNumber:email:phone:customerId:company:billingAddress1:billingAddress2:billingCity:billingState:billingZip:billingCountry:billingPhone:billingEmail:shippingAddress1:shippingAddress2:shippingCity:shippingState:shippingZip:shippingCountry:]` |
| `PayabliTTPPaymentDetails(...)` (struct) | `[[PayabliTTPPaymentDetailsObjC alloc] initWithAmount:serviceFee:currency:paymentDescription:]` |
| `PayabliTTPInvoiceData(...)` (struct) | `[[PayabliTTPInvoiceDataObjC alloc] initWithInvoiceNumber:]` |
| `enum PayabliTTPEvent` w/ associated values | `PayabliTTPEventCode` (`@objc Int`) + `payload` dict — see `PayabliTTPEvent.payload` for per-case schema |
| `enum PayabliTTPError` w/ associated values | `NSError` (domain `"com.payabli.ttp"`, stable per-case `code`) — see `errorCode` table |

All `@objc` callbacks are dispatched on the main thread because the entire
`PayabliTTP` surface is `@MainActor`.

**Maintenance contract.** Any change to the public Swift API — new
method, new event case, new error case, new struct field — **must** be
reflected in the ObjC companion at the same time. The companion is part
of the public API and downstream bridges depend on it. CI tests in
`PayabliTTPObjCInteropTests`, `PayabliTTPEventCodeMappingTests`, and
`PayabliTTPErrorNSErrorTests` lock the integer codes and payload schemas
so silent breakage is caught at build time.

`@Published` setters are `public internal(set)` so the companion extensions
in this folder can mutate state without weakening the public read-only
contract.

### Session — `SessionManager`

`SessionManager.swift` owns the 9-state transition matrix (PRD §17). The
facade calls `transition(to:)` before each phase and `syncPublished()` to
re-publish into its own `@Published` properties. Invalid transitions are
rejected, keeping the machine honest.

### Attestation — `AppAttest*`, `DeviceAttestationService`, `AppAttestor`

| File | Role |
|---|---|
| `DeviceAttestationService.swift` | Protocol the facade depends on (`attest`, `generateAssertion`, `activateDevice`, cache) |
| `AppAttestor.swift` | Apple `DCAppAttestService` seam (`RealAppAttestor` prod, `MockAppAttestor` in tests) |
| `AppAttestService.swift` | Production implementation (class + cache/clear) |
| `AppAttestService+Attest.swift` | `attest()` flow + per-request assertion generation |
| `AppAttestService+Activation.swift` | `/activate` endpoint (consumes an activation code provisioned by the partner) |
| `AppAttestService+Requests.swift` | Shared envelope decoding for the attestation endpoints |
| `AppAttestService+Defaults.swift` | Default hardware-identifier providers (model, OS, device name) |
| `AppAttestWireFormat.swift` | Backend DTOs for the attestation endpoints only |

The split mirrors the facade pattern: one class declaration, one file per
concern. The convenience init on `PayabliTTP` is only available where
`DeviceCheck` can be imported. Package floor is already iOS 16.7 (from
`PayabliCardReaderCore` / `ProximityReader`) and macOS 12 — both well above
`DCAppAttestService`'s own minimums — so no inline `@available` gates are
required. Platforms without `DeviceCheck` must use the designated init
with a custom `DeviceAttestationService`.

### Networking — `TTPConfigClient*`, `TTPTransactionClient*`

Backend clients and their wire formats. DTOs always live in a
`*WireFormat.swift` companion; the client file stays focused on request
building, envelope handling, and error mapping.

| File | Endpoint(s) |
|---|---|
| `TTPConfigClient.swift` | `GET /api/v2/device/taptopay/config/{entry}` (attestation-protected, FR-11B.3) |
| `TTPConfigWireFormat.swift` | `ConfigCredentialsPayload` |
| `TTPTransactionClient.swift` | `POST /api/v2/MoneyIn/initiate`, `PATCH /api/v2/MoneyIn/update/{id}` |
| `TTPTransactionWireFormat.swift` | Initiate / update request-response DTOs, `ProviderResponsePayload` (opaque-JSON vs payload-only) |

Response envelopes shared across both clients (`isSuccess: false` decoding,
`Success<Payload>`, `EmptyPayload`) live in
`PayabliSDKCore/Networking/ResponseEnvelope.swift` under the `PayabliEnvelope`
namespace — don't re-declare them here.

### Persistence — `SecureStorage`, `KeychainStorage`

Only identity tokens survive across launches; everything else is RAM-only.

| File | Persists to | Holds |
|---|---|---|
| `KeychainStorage.swift` (impl of `SecureStorage`) | iOS Keychain | `keyId`, `deviceId` — identity tokens (NFR-5E) |
| `SecureStorage.swift` | — | Protocol + in-memory fake for tests |

Nothing else persists. Credentials, access tokens, Fiserv secrets, and
in-flight transaction bodies: RAM only (NFR-5D).

### Runtime helpers — `EventMulticaster`, `RetryPolicy`

| File | Role |
|---|---|
| `EventMulticaster.swift` | Fan-out of `PayabliTTPEvent` to every `events()` caller (FR-11G.2) |
| `RetryPolicy.swift` | Backoff + jitter for `/update` (PRD §21.1) |

### Provider abstraction — `TapToPayProvider*`, `Adapters/`

| File | Role |
|---|---|
| `TapToPayProvider.swift` | The protocol every adapter implements |
| `TapToPayProviderFactory.swift` | Registry — `providerId` → builder lookup (FR-11A.5..7) |
| `Adapters/` | Concrete implementations. See `Adapters/README.md` for the full contract, credentials policy, error-mapping rules, and onboarding checklist |

---

## 2. Session lifecycle (PRD §17)

The 9-state machine in `PayabliTTPSessionState` is the single source of truth
for what the facade can do next. Every public facade method first asserts
`sessionState ∈ {allowed}` before acting.

```
             ┌──────────────────────────────────────────────┐
             ▼                                              │
.idle ─▶ .attestingDevice ─▶ .fetchingConfig ─▶ .initializingReader ─▶ .ready
  │              │                   │                                  │
  │              └──────┐            └─▶ .pendingActivation ─▶ (back to .idle / .attestingDevice)
  │                     ▼
  │              .pendingActivation
  ▼
.error ◀── (from anywhere on unrecoverable failure)

.ready ─▶ .sessionExpired ─▶ .reinitializing ─▶ .fetchingConfig ─▶ .initializingReader ─▶ .ready
```

The transition matrix lives in `SessionManager.isValidTransition(from:to:)`.
Adding a new state or edge means updating that matrix, the switch in
`PayabliTTPSessionState`, and the relevant facade extension — no other file
needs to change.

---

## 3. State vs events

`SessionManager` and `EventMulticaster` both live on the facade but answer
different questions. The overlap is cosmetic — they fire together because
transitions and announcements usually coincide — but they don't replace each
other.

|  | `SessionManager` | `EventMulticaster` |
|---|---|---|
| Answers | "What can the facade do right now?" | "What just happened?" |
| Shape | Single state (`PayabliTTPSessionState`) | Stream of discrete `PayabliTTPEvent`s |
| Durability | Persistent within the session | Ephemeral — if no one is listening, the event is gone |
| Invariants | Enforced — invalid transitions are rejected | None — fire-and-forget |
| Cardinality | One value, many readers | One event, N subscribers |
| Consumers | Internal guards (`guard sessionState == .ready`), SwiftUI `@Published` bindings | Host apps subscribing via `ttp.events()` — spinners, logs, analytics |

A typical phase in `PayabliTTP+Initialize.swift` touches both:

```swift
_ = sessionManager.transition(to: .attestingDevice)   // state: I can attest
syncPublished()                                        // UI re-renders
multicaster.emit(.attestationStarted)                  // "heads up, I'm attesting"
```

**When to use which?**

- Need to decide whether an operation is legal right now → **state**.
- Need to react to a moment in time (even if the state didn't change) → **event**.
  Example: `.nfcCompleted` fires while the session is still `.ready` both
  before and after. There's no transition, but the host still needs to know
  the tap succeeded.

Collapsing these into one abstraction was considered and rejected — state-only
loses "what just happened" granularity when no transition occurs, and
events-only forces the SDK and its callers to reconstruct "what am I allowed
to do" from a log of past announcements.

---

## 4. Charge pipeline (PRD §19.1)

`PayabliTTP.charge(type:paymentDetails:customer:invoice:orderDescription:)` in `PayabliTTP+Charge.swift` runs three
serial steps. The result of each step feeds the next:

```
┌── /initiate ───────────────────────┐    ┌── provider.startReading ─────┐    ┌── /update ──────────────┐
│ POST /api/v2/MoneyIn/initiate      │    │ CardReadRequest(amount,      │    │ PATCH /MoneyIn/update/  │
│ ← paymentTransId                   │ ─▶ │   merchantTransactionId=...) │ ─▶ │       {paymentTransId}  │
│ (deviceId from attestation cache)  │    │ → CardReadResult             │    │ success: fiservResponse │
└────────────────────────────────────┘    │   (providerResponseJSON)     │    │ failure: error body     │
                                          └──────────────────────────────┘    └─────────────────────────┘
                                                                                      │
                                                                                      ▼
                                                       RetryPolicy.default (5xx only) — on final failure
                                                       the charge throws `PayabliTTPError.updateFailed`.
                                                       There is no offline / pending-update fallback.
```

Every stage emits a `PayabliTTPEvent` through the multicaster so host apps
can surface progress without polling the state machine.

> **Note — no offline fallback.** An earlier version of the SDK enqueued failed
> updates into a `PendingUpdateQueue` for later retry. That subsystem has
> been removed; if the final `PATCH /update` fails after retries, the
> transaction is still authorized on the processor side and the host must
> reconcile manually (processor dashboard or back-office).

---

## 5. Security boundaries

The SDK handles two data classes with different persistence rules:

| Data | Where it lives | Lifetime | Reference |
|---|---|---|---|
| Device bindings: `entry`, `deviceId`, `keyId`, one per paypoint | Keychain (`KeychainStorage`), one item | Until `clearCache(for:)`, the key it names is gone, or device wipe | NFR-5E, PRD §22.1 |
| Install identifier: a UUID minted on first use (`InstallIdentifier`) | Keychain (`KeychainStorage`), one item | Until device wipe or the app's Keychain items are removed. Outlives every binding, and `clearCache(for:)` does not touch it | NFR-5E, PRD §22.1 |
| Pending App Attest key id, one per entry point | Keychain (`KeychainStorage`), one item | Until that key is attested or the paypoint's binding is cleared | NFR-5E, PRD §22.1 |
| Access token, provider credentials (Fiserv), assertions, in-flight transaction bodies | RAM only, adapter + auth objects | Seconds to minutes | NFR-5D |

The install identifier is never sent. What registration receives is a digest of
it with the bundle identifier and this module's name, so the stored value stays
on the device and the value sent differs per app. It has to outlive a binding:
an install that lost it registers as a device that has never been seen.

Nothing else persists to disk. Adapters must drop `self.credentials = nil`
as soon as the processor SDK has its own copy (typically the same call
stack as `prepareReader`). See `Adapters/README.md §3`.

> **Note — activation code is partner-issued.** The SDK does **not** request
> activation codes. When a device lands in `.pendingActivation`, the partner
> must obtain the OTP out-of-band (typically via their admin dashboard
> hitting `POST /api/v2/device/taptopay/activate/challenge` server-side) and
> deliver it to the device user through their own channel. The SDK only
> consumes the code via `activateDevice(activationCode:)`. This keeps
> code-issuance controls — rate limiting, audit, merchant identity — on the
> partner backend, outside the mobile trust zone.

---

## 6. Extending the module

Rules of thumb when adding new capability in this folder:

1. **Keep the folder flat.** No new sub-folders — PRD §7.2 only allows
   `Adapters/`. Use prefixes (`PayabliTTP*`, `AppAttestService+*`,
   `TTPConfigClient*`) instead.
2. **One principal type per file.** DTOs, helpers, and extensions belong in
   companion files (`*WireFormat.swift`, `TypeName+Topic.swift`).
3. **Companion files > giant files.** Once a file crosses ~200 lines or
   mixes concerns (protocol + implementation + DTOs), split into a
   `+Topic.swift` companion.
4. **Wire formats next to their client.** Don't put DTOs in
   `PayabliSDKCore`; keep them alongside the client that owns them so the
   surface is obvious.
5. **Reuse `PayabliEnvelope`.** Any new endpoint that returns the standard
   `isSuccess`/`responseData` envelope should decode via
   `PayabliSDKCore.PayabliEnvelope` rather than rolling its own types.
6. **New states / events / errors stay typed.** Extending the lifecycle
   means updating `PayabliTTPSessionState`, the transition matrix in
   `SessionManager`, `PayabliTTPEvent`, and `PayabliTTPError` together.

For adding a new card-reader implementation, see `Adapters/README.md`.

---

## References

- PRD `§7.2` — directory layout
- PRD `§17` — 9-state session machine
- PRD `§18` — App Attest integration
- PRD `§19.1` — charge pipeline
- PRD `§20` — events + errors
- PRD `§21.1` — retry policy (pending-update queue from §21.2 is no longer implemented)
- PRD `§22.1` — Keychain persistence
- PRD `FR-11A..E..J`, `NFR-5D`, `NFR-5E`
- `Adapters/README.md` — provider contract and onboarding
