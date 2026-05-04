# Tap to Pay Adapters

Concrete `TapToPayProvider` implementations live in this folder. Each adapter
wraps a specific processor SDK (Fiserv today, other tomorrow)
and exposes it through the processor-agnostic contract that `PayabliTTP`
consumes.

Folder layout is fixed by PRD §7.2. Every adapter and its companion files
live here; no sub-folders.

---

## 1. Contract — `TapToPayProvider`

Defined in `../TapToPayProvider.swift`. The facade calls these six methods in
the order shown below.

| Method | When the facade calls it | Adapter must do |
|---|---|---|
| `static var providerId: String` | `TapToPayProviderFactory` lookup and `CardReadResult.provider` | Return a stable identifier (`"fiserv"`, `"visa"`, ...). Goes into the API payload `provider` field so the backend routes decryption correctly (FR-11J.3). |
| `checkEligibility() async` | Before any UI, before `/config` is fetched | Validate platform, OS version, hardware (e.g. `PaymentCardReader.isSupported`). **Must not require credentials.** |
| `configure(credentials: [String:String]) throws` | After `/config` returns `providerCredentials` | Validate required keys, map to a typed struct, stash it in `self`. Throw `PayabliTTPError.readerSetupFailed(reason:)` on missing / malformed input. |
| `prepareReader() async throws` | Right after `configure(...)` | Build the processor SDK's reader, request session token, link account if needed, initialize session. **Drop `self.credentials` as soon as the SDK has its own copy.** |
| `startReading(_ request: CardReadRequest) async throws -> CardReadResult` | `PayabliTTP.charge(...)` | Run the NFC interaction. Atomic providers (Fiserv) also charge here and return the full processor response. Payload-only providers populate `encryptedPayload` instead. |
| `cancelReading() async` | User cancelled the tap | Tear down the active reader and clear `self.credentials`. |
| `cleanUp() async` | End of session | Same as cancel — full teardown. |

---

## 2. `CardReadRequest` → `CardReadResult`

Defined in `../../Models/TapToPayCardRead.swift`.

**Request** carries:
- `amount: Decimal` — round using your processor's rule (Fiserv uses bankers').
- `merchantTransactionId: String` — Payabli's `paymentTransId` from
  `/initiate`. Wire it to the processor's merchant-correlation field (for
  Fiserv: `merchantTransactionId` + `merchantOrderId`).
- `merchantOrderId`, `merchantInvoiceNumber`, `customer`, `order` —
  pass-through; use if the processor SDK has slots for them, otherwise log
  for audit and drop. Never `nil` for `customer` / `order` (empty structs
  instead).

**Result** must be populated for one of two flows:

| Flow | `encryptedPayload` | `providerResponseJSON` |
|---|---|---|
| Atomic (Fiserv) — SDK charges during the tap | `Data()` | Full processor response JSON (forwarded verbatim under `fiservResponse` in the PATCH update body) |
| Payload-only (legacy) — SDK only collects card data, backend charges | Encrypted blob | `nil` |

Always set `provider: Self.providerId`. Set `cardNetwork` when you can extract
it cheaply (Fiserv: `card.brand`). `providerMetadata` is forwarded as-is to
the API, so only put string-safe audit info there.

---

## 3. Credentials policy (NFR-5D)

**Hard rule:** credentials never touch disk, Keychain, UserDefaults, or any
persistence. RAM only.

The adapter contract is stricter than "RAM only" — the target ventana for
`self.credentials` is **milliseconds**:

```
configure(credentials:)            ← stored in self.credentials
        ↓
prepareReader()
  └─ buildReader(credentials:)     ← passed into the processor SDK
  └─ self.credentials = nil        ← drop immediately
  └─ requestSessionToken / etc.    ← no longer need them
```

After `prepareReader` returns, credentials survive only inside the processor
SDK's own config object. `cancelReading` / `cleanUp` must release that by
destroying the reader.

Consequence: any retry / re-initialize needs a fresh `/config` fetch. The
facade (`PayabliTTP+Initialize.swift → reinitializeIfNeeded`) already handles
this, so don't cache credentials yourself to "optimize" retries.

---

## 4. Error mapping

Every throwing path must surface a `PayabliTTPError`. Pick the case that
matches where in the pipeline the failure happened:

| Situation | Case |
|---|---|
| Missing / malformed credentials, reader fails to initialize | `.readerSetupFailed(reason:)` |
| NFC tap failed, processor rejected the charge, user cancelled | `.nfcFailed(reason:)` |
| Called `startReading` before `prepareReader` | `.readerSetupFailed(reason: "Reader not prepared")` |

**User cancellation** should be encoded inside `.nfcFailed` with the
`cancellationReasonPrefix` constant from `FiservCardReader+Errors.swift`
(`"cancelled:"`) so hosts can distinguish it by substring. If you add a new
adapter, expose the same prefix constant for consistency.

Don't re-wrap errors that are already `PayabliTTPError` — forward them.

Put the mapping logic in a companion file named `XxxCardReader+Errors.swift`,
matching the Fiserv layout.

---

## 5. File layout convention

```
Adapters/
├── README.md                          ← this file
├── FiservCardReader.swift             ← main implementation
├── FiservCardReader+Errors.swift      ← error mapping
└── VisaCardReader.swift               ← hypothetical next adapter
    VisaCardReader+Errors.swift
```

Rules:
- Main file holds the class, `Credentials` struct, `configure`, `prepareReader`,
  `startReading`, `cancelReading`, `cleanUp`, `clearAllState`.
- Any cross-cutting concern > ~60 lines gets a companion `+<Topic>.swift`
  file in the **same** folder. Never create sub-folders.
- Class name ends in `CardReader` (for contactless) — convention, not enforced.
- Private helpers used only by the main file stay in the main file; once they
  grow or are used across topics, extract with `+Topic` suffix.

---

## 6. Registering a new adapter

In the host app or SDK bootstrap, register a builder with the factory:

```swift
TapToPayProviderFactory.shared.register(providerId: VisaCardReader.providerId) {
    VisaCardReader()
}
```

The facade resolves the provider via `TapToPayProviderFactory.shared.build(providerId:)`.
`FiservCardReader` currently wires itself via the `PayabliTTP.init(...)`
convenience initializer; a second adapter would follow the same pattern
(new convenience init or let the host inject it via the designated init).

---

## 7. Checklist for a new adapter

1. `XxxCardReader.swift` in this folder, `public final class XxxCardReader: TapToPayProvider, @unchecked Sendable`.
2. Nested `public struct Credentials: Sendable` + `configure(credentials: [String:String])` that maps the `/config` dict to it.
3. `requiredCredentialKeys` / `optionalCredentialKeys` static arrays; log a warning for missing optionals.
4. `checkEligibility()` never reads credentials.
5. `prepareReader()` drops `self.credentials = nil` right after the processor SDK has its own copy.
6. Any failure inside `prepareReader()` calls `clearAllState()` before throwing.
7. `cancelReading()` and `cleanUp()` both call `clearAllState()`.
8. `XxxCardReader+Errors.swift` with `mapError(_:fallback:)` and `cancellationReasonPrefix`.
9. Unit tests: `XxxCardReaderTests.swift` under `Tests/PayabliSDKTapToPayTests/` covering eligibility, `configure` validation, and the `cleanUp → prepareReader` failure path.
10. Register with `TapToPayProviderFactory`.
11. Verify `swift build` + `swift test --filter PayabliSDKTapToPayTests` are green.

---

## References

- `../TapToPayProvider.swift` — protocol
- `../TapToPayProviderFactory.swift` — registry
- `../../Models/TapToPayCardRead.swift` — `CardReadRequest` / `CardReadResult`
- `../PayabliTTPEvent.swift` — `PayabliTTPError` cases
- `FiservCardReader.swift` + `FiservCardReader+Errors.swift` — reference implementation
- PRD §7.2 (directory layout), FR-11A (provider abstraction), FR-11B (Fiserv), NFR-5D (runtime-only credentials)
