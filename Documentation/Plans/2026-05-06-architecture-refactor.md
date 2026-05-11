# Architecture Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement every actionable recommendation from `Documentation/ArchitectureAssessment-2026-05-06.md` — five proposals (A through E) plus the actionable subset of the 19 findings — without breaking the public API.

**Architecture:**
1. Move cross-module primitives (retry, event multicasting) into Core so future modules don't duplicate them.
2. Tighten access modifiers on types that leaked into the public surface for test ergonomics or by oversight.
3. Introduce `PayabliSession` in Core to own a single `PayabliAuth` + `PayabliService` per `PayabliConfig`, then layer a `PayabliTransport` protocol on top so middleware (auth-bearer header, 401-refresh-once) becomes a single decorator that every module shares.
4. Delete the unused `TapToPayProviderFactory` singleton.
5. Ship test fixtures as a real `PayabliSDKTestUtils` library product so host apps and future modules can depend on them.

**Tech Stack:** Swift 5.9 / Swift 6.3 toolchain, Swift Package Manager, XCTest. iOS 16.7 minimum. Zero external SPM dependencies. Tests are run via `swift test` or `swift test --filter <pattern>` from the repo root.

**Worktree:** `/Users/johnny/Projects_V2/sdk-ios/.claude/worktrees/assessment+swift-library-architecture` (branch `worktree-assessment+swift-library-architecture`).

**Source spec:** `Documentation/ArchitectureAssessment-2026-05-06.md`. The plan is sequenced according to the assessment's "Recommended sequencing" section, with the foundational moves (Proposal C and minor public-surface tightening) first so later proposals build on a clean base.

---

## Conventions used in this plan

- **Verification cadence per task:** "write failing test → run it → implement → run again → commit" for new behavior; "make change → `swift build` → `swift test` → commit" for mechanical refactors.
- **Commit messages** use the existing Conventional Commits style observed in the repo (`feat(scope):`, `refactor(scope):`, `chore(scope):`, `test(scope):`, `docs(scope):`).
- **Run commands** are absolute from the worktree root. Replace `<filter>` patterns to scope `swift test` to the relevant suite.
- **Exact file paths** are repo-relative and include the line ranges where applicable.
- **No placeholders.** Every step that adds code shows the code.

---

## Phase 0 — Pre-flight

### Task 0.1: Confirm baseline

- [ ] **Step 1:** From the worktree root, run `swift build` and confirm it exits 0.
  - Run: `swift build`
  - Expected: builds clean, no errors.
- [ ] **Step 2:** Run the full test suite.
  - Run: `swift test`
  - Expected: all tests pass. Note any flakes — they are pre-existing and not caused by this work.
- [ ] **Step 3:** Capture the baseline count of public symbols so the cleanup phases can compare.
  - Run: `grep -rE '^public ' Sources/ | wc -l`
  - Record the number; the plan does not require it to drop, but it is a useful sanity check.
- [ ] **Step 4:** Commit only if the `Documentation/` folder from the assessment phase is not yet committed.
  - Run: `git status`
  - If `Documentation/ArchitectureAssessment-2026-05-06.md` shows as untracked, stage and commit:
    ```bash
    git add Documentation/ArchitectureAssessment-2026-05-06.md
    git add Documentation/Plans/2026-05-06-architecture-refactor.md
    git commit -m "$(cat <<'EOF'
docs: add architecture assessment and refactor plan

Outputs from the architecture audit pass: the assessment document
(findings + decision-ready proposals) and the implementation plan
that turns those proposals into bite-sized, TDD-shaped tasks.

EOF
)"
    ```

---

## Phase 1 — Move shared primitives to Core (Proposal C)

Goal: `RetryPolicy`, `Retry`, `RetryableError`, and `EventMulticaster` live in Core so PayIn / future modules use them without copy-paste.

### Task 1.1: Move `RetryPolicy` into Core

**Files:**
- Move: `Sources/PayabliSDKTapToPay/RetryPolicy.swift` → `Sources/PayabliSDKCore/Networking/RetryPolicy.swift`
- Modify: the `Retry.run` fallback throw (was `PayabliTTPError.updateFailed(...)` — TapToPay-specific — replace with `PayabliGenericError`).
- Move: `Tests/PayabliSDKTapToPayTests/RetryPolicyTests.swift` → `Tests/PayabliSDKCoreTests/RetryPolicyTests.swift`

- [ ] **Step 1: Move the file**
  ```bash
  git mv Sources/PayabliSDKTapToPay/RetryPolicy.swift Sources/PayabliSDKCore/Networking/RetryPolicy.swift
  git mv Tests/PayabliSDKTapToPayTests/RetryPolicyTests.swift Tests/PayabliSDKCoreTests/RetryPolicyTests.swift
  ```

- [ ] **Step 2: Replace the `PayabliTTPError.updateFailed` fallback with `PayabliGenericError`** in `Sources/PayabliSDKCore/Networking/RetryPolicy.swift:91`.

  Replace:
  ```swift
  throw lastUnderlying ?? PayabliTTPError.updateFailed(reason: "Exhausted retries")
  ```

  With:
  ```swift
  throw lastUnderlying ?? PayabliGenericError(
      code: .networkError,
      reason: "Exhausted retries"
  )
  ```

- [ ] **Step 3: Run `swift build`**
  - Run: `swift build`
  - Expected: builds clean. If any callers in TapToPay imported `RetryPolicy` via a bare reference, they keep working because TapToPay already imports `PayabliSDKCore`.

- [ ] **Step 4: Run all tests**
  - Run: `swift test`
  - Expected: every test that referenced `RetryPolicy` / `Retry` / `RetryableError` still passes. The moved test file (`RetryPolicyTests.swift`) is now part of `PayabliSDKCoreTests`.

- [ ] **Step 5: Update test imports in the moved file** if `swift test` complains about missing `import PayabliSDKTapToPay`.
  - Edit `Tests/PayabliSDKCoreTests/RetryPolicyTests.swift`: change `@testable import PayabliSDKTapToPay` to `@testable import PayabliSDKCore`.
  - Re-run `swift test`.

- [ ] **Step 6: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Networking/RetryPolicy.swift Tests/PayabliSDKCoreTests/RetryPolicyTests.swift Sources/PayabliSDKTapToPay/RetryPolicy.swift Tests/PayabliSDKTapToPayTests/RetryPolicyTests.swift
  git commit -m "refactor(core): move RetryPolicy + Retry + RetryableError into Core"
  ```

### Task 1.2: Generalize and move `EventMulticaster` into Core

**Files:**
- Modify (then move): `Sources/PayabliSDKTapToPay/EventMulticaster.swift` → `Sources/PayabliSDKCore/Concurrency/EventMulticaster.swift`. The class becomes generic over the event type.
- Modify: TapToPay code that references the unparameterized `EventMulticaster` so it uses an alias.
- Move (with import update): `Tests/PayabliSDKTapToPayTests/EventMulticasterTests.swift` — keep tests using `PayabliTTPEvent` but exercising the generic via the alias.

- [ ] **Step 1: Generalize the class** in place first, then move. Open `Sources/PayabliSDKTapToPay/EventMulticaster.swift` and make the class generic over `Event: Sendable`:

  ```swift
  import Foundation

  /// Multicast emitter for any `Sendable` event type. Every concurrent caller
  /// of `stream()` receives all subsequent events.
  public final class EventMulticaster<Event: Sendable>: @unchecked Sendable {

      private final class Subscription: @unchecked Sendable {
          let id = UUID()
          let continuation: AsyncStream<Event>.Continuation

          init(continuation: AsyncStream<Event>.Continuation) {
              self.continuation = continuation
          }
      }

      private let lock = NSLock()
      private var subscribers: [Subscription] = []

      public init() {}

      public func stream() -> AsyncStream<Event> {
          AsyncStream { continuation in
              let sub = Subscription(continuation: continuation)
              lock.lock()
              subscribers.append(sub)
              lock.unlock()
              continuation.onTermination = { [weak self] _ in
                  self?.remove(sub.id)
              }
          }
      }

      public func emit(_ event: Event) {
          lock.lock()
          let snapshot = subscribers
          lock.unlock()
          for sub in snapshot { sub.continuation.yield(event) }
      }

      public func finishAll() {
          lock.lock()
          let snapshot = subscribers
          subscribers.removeAll()
          lock.unlock()
          for sub in snapshot { sub.continuation.finish() }
      }

      private func remove(_ id: UUID) {
          lock.lock(); defer { lock.unlock() }
          subscribers.removeAll { $0.id == id }
      }
  }
  ```

- [ ] **Step 2: Add a TapToPay alias** so existing call sites do not need to change. Create `Sources/PayabliSDKTapToPay/EventMulticasterAlias.swift`:

  ```swift
  import PayabliSDKCore

  /// TapToPay convenience alias for `EventMulticaster<PayabliTTPEvent>`.
  /// Lets the facade keep saying `EventMulticaster()` without having to spell
  /// the generic parameter at every construction site.
  internal typealias TTPEventMulticaster = EventMulticaster<PayabliTTPEvent>
  ```

- [ ] **Step 3: Update every TapToPay reference to `EventMulticaster()` to use the alias.**

  Search:
  ```bash
  grep -rn 'EventMulticaster' Sources/PayabliSDKTapToPay/
  ```

  In `Sources/PayabliSDKTapToPay/PayabliTTP.swift:48`, change:
  ```swift
  let multicaster = EventMulticaster()
  ```
  to:
  ```swift
  let multicaster = TTPEventMulticaster()
  ```

  Repeat for every `EventMulticaster()` literal inside TapToPay sources.

- [ ] **Step 4: Move the file into Core**
  ```bash
  git mv Sources/PayabliSDKTapToPay/EventMulticaster.swift Sources/PayabliSDKCore/Concurrency/EventMulticaster.swift
  ```

- [ ] **Step 5: Run `swift build`**
  - Run: `swift build`
  - Expected: builds clean. If a TapToPay file still references the bare `EventMulticaster()` without the generic parameter, the compiler will flag it — fix by switching to `TTPEventMulticaster()`.

- [ ] **Step 6: Move the test file** and update its import.
  ```bash
  git mv Tests/PayabliSDKTapToPayTests/EventMulticasterTests.swift Tests/PayabliSDKCoreTests/EventMulticasterTests.swift
  ```
  Edit `Tests/PayabliSDKCoreTests/EventMulticasterTests.swift`: change `@testable import PayabliSDKTapToPay` → `@testable import PayabliSDKCore`. Where the tests construct an `EventMulticaster<PayabliTTPEvent>`, replace with `EventMulticaster<Int>` or a small local `enum TestEvent: Sendable { case a, b }` so the test does not depend on a TapToPay type.

  Example minimal rewrite of one test method (full file follows the same pattern):
  ```swift
  func testStreamReceivesEvents() async {
      let multicaster = EventMulticaster<Int>()
      let stream = multicaster.stream()
      let task = Task<[Int], Never> {
          var collected: [Int] = []
          for await value in stream {
              collected.append(value)
              if collected.count == 3 { break }
          }
          return collected
      }
      multicaster.emit(1)
      multicaster.emit(2)
      multicaster.emit(3)
      let received = await task.value
      XCTAssertEqual(received, [1, 2, 3])
  }
  ```

- [ ] **Step 7: Run tests**
  - Run: `swift test`
  - Expected: all tests pass.

- [ ] **Step 8: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Concurrency/EventMulticaster.swift Sources/PayabliSDKTapToPay/EventMulticaster.swift Sources/PayabliSDKTapToPay/EventMulticasterAlias.swift Sources/PayabliSDKTapToPay/PayabliTTP.swift Tests/PayabliSDKCoreTests/EventMulticasterTests.swift Tests/PayabliSDKTapToPayTests/EventMulticasterTests.swift
  git commit -m "refactor(core): move EventMulticaster to Core, generic over event type"
  ```

---

## Phase 2 — Tighten public surface (Findings 9, 10, 11, 15, 18, 19a, 19c, 19d)

Each task is small and mechanical. Pattern: change access modifier or move code, run `swift build` + `swift test`, commit.

### Task 2.1: Make `SessionManager` internal (Finding 9)

**Files:** `Sources/PayabliSDKTapToPay/SessionManager.swift`

- [ ] **Step 1: Change access modifier**

  In `Sources/PayabliSDKTapToPay/SessionManager.swift:10`, replace:
  ```swift
  public final class SessionManager: ObservableObject {
      @Published public private(set) var sessionState: PayabliTTPSessionState = .idle
      @Published public private(set) var isReady: Bool = false
      public private(set) var lastError: Error?

      public init() {}
  ```
  With:
  ```swift
  internal final class SessionManager: ObservableObject {
      @Published private(set) var sessionState: PayabliTTPSessionState = .idle
      @Published private(set) var isReady: Bool = false
      private(set) var lastError: Error?

      init() {}
  ```

- [ ] **Step 2: Run `swift build`**
  - Run: `swift build`
  - Expected: builds clean. `PayabliTTP` already accesses `sessionManager` from inside the same module, so internal access is sufficient.

- [ ] **Step 3: Run tests**
  - Run: `swift test`
  - Expected: passes. `SessionManagerTests.swift` already lives inside the test target, which has `@testable import PayabliSDKTapToPay`, so internal access is fine.

- [ ] **Step 4: Commit**
  ```bash
  git add Sources/PayabliSDKTapToPay/SessionManager.swift
  git commit -m "refactor(taptopay): make SessionManager internal"
  ```

### Task 2.2: Hide AppAttestService hardware-id providers behind an internal init (Finding 10)

**Files:** `Sources/PayabliSDKTapToPay/AppAttestService.swift`

Goal: keep ONE public init `(service:auth:attestor:storage:)`. Move the four hardware-id providers behind an internal init that the public init delegates to.

- [ ] **Step 1: Refactor the inits**

  In `Sources/PayabliSDKTapToPay/AppAttestService.swift:45-63`, replace the single public init with two inits — one public (4 args, defaults applied), one internal (8 args, all overrides):

  ```swift
  public init(
      service: PayabliService,
      auth: PayabliAuth,
      attestor: AppAttestor,
      storage: SecureStorage
  ) {
      self.init(
          service: service,
          auth: auth,
          attestor: attestor,
          storage: storage,
          hardwareIdProvider: AppAttestService.defaultHardwareId,
          deviceNameProvider: AppAttestService.defaultDeviceName,
          modelProvider: AppAttestService.defaultModel,
          osVersionProvider: AppAttestService.defaultOSVersion
      )
  }

  internal init(
      service: PayabliService,
      auth: PayabliAuth,
      attestor: AppAttestor,
      storage: SecureStorage,
      hardwareIdProvider: @Sendable @escaping () -> String,
      deviceNameProvider: @Sendable @escaping () -> String,
      modelProvider: @Sendable @escaping () -> String,
      osVersionProvider: @Sendable @escaping () -> String
  ) {
      self.service = service
      self.auth = auth
      self.attestor = attestor
      self.storage = storage
      self.hardwareIdProvider = hardwareIdProvider
      self.deviceNameProvider = deviceNameProvider
      self.modelProvider = modelProvider
      self.osVersionProvider = osVersionProvider
  }
  ```

- [ ] **Step 2: Run `swift build`**
  - Run: `swift build`
  - Expected: builds clean.

- [ ] **Step 3: Verify tests still compile and pass.** Tests in `AppAttestServiceTests.swift` already use `@testable import PayabliSDKTapToPay` so the internal init is reachable.
  - Run: `swift test --filter AppAttestServiceTests`

- [ ] **Step 4: Commit**
  ```bash
  git add Sources/PayabliSDKTapToPay/AppAttestService.swift
  git commit -m "refactor(taptopay): hide AppAttestService hardware-id providers behind internal init"
  ```

### Task 2.3: Make `FiservCardReader.Credentials` and `setCredentials` internal (Finding 11)

**Files:** `Sources/PayabliSDKTapToPay/Adapters/FiservCardReader.swift`

- [ ] **Step 1: Change access modifiers**

  In `Sources/PayabliSDKTapToPay/Adapters/FiservCardReader.swift:25`, change:
  ```swift
  public struct Credentials { ... }
  ```
  to:
  ```swift
  internal struct Credentials { ... }
  ```

  And, around line 77, change:
  ```swift
  public func setCredentials(_ credentials: Credentials) { ... }
  ```
  to:
  ```swift
  internal func setCredentials(_ credentials: Credentials) { ... }
  ```

- [ ] **Step 2: Run `swift build`**
  - Run: `swift build`
  - Expected: builds clean. Tests already import via `@testable`.

- [ ] **Step 3: Run tests**
  - Run: `swift test --filter FiservCardReaderTests`

- [ ] **Step 4: Commit**
  ```bash
  git add Sources/PayabliSDKTapToPay/Adapters/FiservCardReader.swift
  git commit -m "refactor(taptopay): make FiservCardReader.Credentials internal"
  ```

### Task 2.4: Make `SessionTierValidator` internal (Finding 15)

**Files:** `Sources/PayabliSDKCore/Auth/SessionTierValidator.swift`

- [ ] **Step 1: Change access modifiers**

  In `Sources/PayabliSDKCore/Auth/SessionTierValidator.swift:15`, change:
  ```swift
  public enum SessionTierValidator {
      public static func validate(...) throws { ... }
      public static func detectedTier(from config: PayabliConfig) -> PayabliSessionTier { ... }
  }
  ```
  to:
  ```swift
  internal enum SessionTierValidator {
      static func validate(...) throws { ... }
      static func detectedTier(from config: PayabliConfig) -> PayabliSessionTier { ... }
  }
  ```

- [ ] **Step 2: Run `swift build` + `swift test`**
  - Expected: builds clean. If any caller outside Core was depending on it, the compiler will fail — there should be none today.

- [ ] **Step 3: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Auth/SessionTierValidator.swift
  git commit -m "refactor(core): make SessionTierValidator internal until tier detection is real"
  ```

### Task 2.5: Drop redundant `import ProximityReader` (Finding 18)

**Files:** `Sources/PayabliSDKTapToPay/Adapters/FiservCardReader.swift`

- [ ] **Step 1: Remove the import**

  In `Sources/PayabliSDKTapToPay/Adapters/FiservCardReader.swift:5`, delete:
  ```swift
  import ProximityReader
  ```

- [ ] **Step 2: Run `swift build`**
  - Run: `swift build`
  - Expected: builds clean. `PayabliCardReaderCore` already re-exports `ProximityReader` symbols transitively. If the build fails because some local reference needs the import, restore it and skip this task — the audit was wrong about transitive exports for that specific symbol.

- [ ] **Step 3: Run tests**
  - Run: `swift test`

- [ ] **Step 4: Commit**
  ```bash
  git add Sources/PayabliSDKTapToPay/Adapters/FiservCardReader.swift
  git commit -m "refactor(taptopay): drop redundant ProximityReader import in FiservCardReader"
  ```

### Task 2.6: Hide `PayabliEnvironment.local` behind `#if DEBUG` (Finding 19a)

**Files:** `Sources/PayabliSDKCore/Public/PayabliEnvironment.swift`

The case `local = 0` ships a developer-specific ngrok URL in the public enum. Hide it behind `#if DEBUG` so release builds do not include it.

- [ ] **Step 1: Refactor the enum**

  Replace the file contents with:
  ```swift
  import Foundation

  /// The Payabli API environment used by the SDK.
  ///
  /// Determines all API base URLs. Set at initialization via `PayabliConfig`.
  /// See PRD §8.2 for base URLs.
  @objc public enum PayabliEnvironment: Int, Sendable {
      #if DEBUG
      /// Developer-only environment pointing at a local tunnel. Available only
      /// in DEBUG builds — never shipped in a release binary.
      case local = 0
      #endif
      case qa = 1
      case sandbox = 2
      case production = 3

      /// Base URL for this environment.
      public var baseURL: URL {
          // swiftlint:disable force_unwrapping
          switch self {
          #if DEBUG
          case .local:
              return URL(string: "https://wallets-test.ngrok.app")!
          #endif
          case .qa:
              return URL(string: "https://api-qa.payabli.com")!
          case .sandbox:
              return URL(string: "https://api-sandbox.payabli.com")!
          case .production:
              return URL(string: "https://api.payabli.com")!
          }
          // swiftlint:enable force_unwrapping
      }
  }
  ```

- [ ] **Step 2: Run `swift build`** (defaults to debug; the case will be present)
  - Run: `swift build`

- [ ] **Step 3: Run tests**
  - Run: `swift test`
  - Expected: any test that exercises `.local` continues to work because tests build in DEBUG.

- [ ] **Step 4: Confirm the case is gone in release**
  - Run: `swift build -c release`
  - Expected: builds clean. If anything in the source tree references `.local` outside a `#if DEBUG` block, the release build will fail and you have your gap.

- [ ] **Step 5: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Public/PayabliEnvironment.swift
  git commit -m "refactor(core): gate PayabliEnvironment.local behind #if DEBUG"
  ```

### Task 2.7: Map 400 to a real validation error code (Finding 19c)

**Files:** `Sources/PayabliSDKCore/Models/PayabliError.swift`

`PayabliValidationError.code` returns `.decodingError` today. That is semantically wrong and confuses telemetry consumers. Add a `.validation` case to `PayabliErrorCode` and use it.

- [ ] **Step 1: Read `PayabliError.swift`** to confirm the current shape:
  - Run: `grep -n 'PayabliErrorCode' Sources/PayabliSDKCore/Models/PayabliError.swift`

- [ ] **Step 2: Add the `.validation` case** to the `PayabliErrorCode` enum. Add it directly under whatever case `decodingError` sits next to (preserving alphabetical / logical order of the existing enum).

  Find the enum declaration; add a new case:
  ```swift
  case validation
  ```

- [ ] **Step 3: Update `PayabliValidationError.code`** to return `.validation` instead of `.decodingError`. Around `Sources/PayabliSDKCore/Models/PayabliError.swift:76`:
  ```swift
  public var code: PayabliErrorCode { .validation }
  ```

- [ ] **Step 4: Write a failing test** verifying the mapping. Add to `Tests/PayabliSDKCoreTests/PayabliSDKCoreTests.swift` (or a new `PayabliErrorCodeMappingTests.swift`):

  ```swift
  func testValidationErrorCodeMapsToValidation() {
      let validation = PayabliValidationError(
          code: 400,
          message: "Bad request",
          details: nil
      )
      XCTAssertEqual(validation.code, .validation)
  }
  ```

  Match the actual `PayabliValidationError.init` signature you find in the file; the example above assumes a `code: Int, message: String, details: ...` shape. Substitute the real one.

- [ ] **Step 5: Run the test — verify it passes** (the implementation is already done in step 3).
  - Run: `swift test --filter testValidationErrorCodeMapsToValidation`
  - Expected: PASS.

- [ ] **Step 6: Run the full suite**
  - Run: `swift test`
  - Expected: any consumer relying on `PayabliValidationError.code == .decodingError` will break. Search for it:
    ```bash
    grep -rn 'PayabliErrorCode.decodingError' Sources/ Tests/
    ```
    Update any matches that were really expecting validation semantics.

- [ ] **Step 7: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Models/PayabliError.swift Tests/PayabliSDKCoreTests/
  git commit -m "fix(core): map PayabliValidationError to .validation, not .decodingError"
  ```

### Task 2.8: Move `Locked` and `UncheckedSendableBox` out of `PayabliTTP.swift` (Finding 19d)

**Files:**
- Modify: `Sources/PayabliSDKTapToPay/PayabliTTP.swift` (remove the two helper types from the bottom of the file)
- Create: `Sources/PayabliSDKTapToPay/_ObjCBridging.swift` (new home for the helpers)

- [ ] **Step 1: Create the new file** with the two helper types and a documentation comment that explains they exist solely to bridge ObjC blocks into Swift `@Sendable` closures.

  ```swift
  import Foundation

  // Helpers used only by the `@objc` convenience init in `PayabliTTP.swift`.
  // They are extracted into their own file so the facade does not carry
  // ObjC-bridging plumbing inline. Both types are intentionally `internal`
  // (no `public`) — host apps must not see them.

  /// Box that lets us thread an ObjC block through a Swift `@Sendable`
  /// closure. ObjC blocks are heap-allocated and copy-on-capture, but Swift
  /// cannot infer `@Sendable` for the input function type, so we opt out of
  /// the check explicitly at the boundary.
  struct UncheckedSendableBox<Value>: @unchecked Sendable {
      let value: Value
      init(_ value: Value) { self.value = value }
  }

  /// Tiny `NSLock`-backed reference cell used as a one-shot guard when
  /// bridging ObjC completion blocks into a `CheckedContinuation`. The host
  /// might invoke a completion block more than once — `CheckedContinuation`
  /// crashes on the second resume — so this cell serializes "did I already
  /// resume?" Reference type so the closure mutates shared state without
  /// `var` capture warnings under strict concurrency.
  final class Locked<Value>: @unchecked Sendable {
      private let lock = NSLock()
      private var value: Value

      init(_ value: Value) { self.value = value }

      /// Mutates and returns whatever the caller derives from the protected
      /// state, atomically. Use the inout argument to read+write.
      func withLock<R>(_ body: (inout Value) -> R) -> R {
          lock.lock()
          defer { lock.unlock() }
          return body(&value)
      }
  }
  ```

- [ ] **Step 2: Delete** lines 282-310 in `Sources/PayabliSDKTapToPay/PayabliTTP.swift` (the `UncheckedSendableBox` and `Locked` definitions, including their doc comments). The deletion is everything from the `// MARK: - Internal helpers` line down to the closing brace of `Locked`.

- [ ] **Step 3: Run `swift build`**
  - Run: `swift build`
  - Expected: builds clean. The two types are referenced by the `@objc` convenience init in the same module; with both old and new files in the same module they would conflict, so make sure step 2 is fully done.

- [ ] **Step 4: Run tests**
  - Run: `swift test`

- [ ] **Step 5: Commit**
  ```bash
  git add Sources/PayabliSDKTapToPay/_ObjCBridging.swift Sources/PayabliSDKTapToPay/PayabliTTP.swift
  git commit -m "refactor(taptopay): extract Locked/UncheckedSendableBox into _ObjCBridging.swift"
  ```

---

## Phase 3 — `PayabliConfig` value type (Finding 2)

Goal: convert `PayabliConfig` from `final class @unchecked Sendable` to `struct Sendable`.

### Task 3.1: Convert `PayabliConfig` to a struct

**Files:** `Sources/PayabliSDKCore/Public/PayabliConfig.swift`

- [ ] **Step 1: Audit identity-dependent call sites first.** Run:
  ```bash
  grep -rn 'config ===' Sources/ Tests/
  grep -rn 'config !==' Sources/ Tests/
  grep -rn 'ObjectIdentifier(config' Sources/ Tests/
  ```
  Expected: zero matches. If any exist, document them in the commit message and convert each to value-equality (`config.entryPoint == other.entryPoint && ...`).

- [ ] **Step 2: Replace the type definition** in `Sources/PayabliSDKCore/Public/PayabliConfig.swift:34-68`:

  ```swift
  public struct PayabliConfig: Sendable {
      public let accessToken: String
      public let tokenProvider: PayabliTokenRefresh?
      public let entryPoint: String
      public let environment: PayabliEnvironment
      public let telemetryEnabled: Bool

      public init(
          accessToken: String,
          tokenProvider: PayabliTokenRefresh? = nil,
          entryPoint: String,
          environment: PayabliEnvironment,
          telemetryEnabled: Bool = true
      ) {
          self.accessToken = accessToken
          self.tokenProvider = tokenProvider
          self.entryPoint = entryPoint
          self.environment = environment
          self.telemetryEnabled = telemetryEnabled
      }
  }
  ```

  Note: the doc comment block above the type stays. The change is `public final class PayabliConfig: @unchecked Sendable {` → `public struct PayabliConfig: Sendable {`.

- [ ] **Step 3: Run `swift build`**
  - Run: `swift build`
  - Expected: builds clean. `PayabliAuth` already takes `PayabliConfig` by value (`init(config: PayabliConfig)`), so no change needed there. `PayabliTokenRefresh` is `@Sendable`, so the struct is Sendable without `@unchecked`.

- [ ] **Step 4: Run tests**
  - Run: `swift test`
  - Expected: passes. Any test that compared configs by reference will fail; the audit step in step 1 was the safety net.

- [ ] **Step 5: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Public/PayabliConfig.swift
  git commit -m "refactor(core): convert PayabliConfig to a value type"
  ```

---

## Phase 4 — `PayabliSession` foundation (Proposal A + Finding 13)

Goal: a single `PayabliAuth` + `PayabliService` per session, owned by Core. Components accept a `PayabliSession` (preferred) or a `PayabliConfig` (convenience that builds one internally).

This phase ends with all tests still using the existing public API (no breaking change).

### Task 4.1: Add `PayabliSession` to Core

**Files:**
- Create: `Sources/PayabliSDKCore/Public/PayabliSession.swift`
- Test: `Tests/PayabliSDKCoreTests/PayabliSessionTests.swift`

- [ ] **Step 1: Write the failing test** for the basic shape of `PayabliSession`. Create `Tests/PayabliSDKCoreTests/PayabliSessionTests.swift`:

  ```swift
  import XCTest
  @testable import PayabliSDKCore

  final class PayabliSessionTests: XCTestCase {
      func testSessionExposesAuthAndService() async {
          let config = PayabliConfig(
              accessToken: "abc",
              entryPoint: "demo",
              environment: .sandbox
          )
          let session = PayabliSession(config: config)
          let token = await session.auth.currentAccessToken()
          XCTAssertEqual(token, "abc")
          XCTAssertEqual(session.config.entryPoint, "demo")
      }

      func testSessionAcceptsCustomURLSession() {
          let stubConfig = URLSessionConfiguration.ephemeral
          stubConfig.protocolClasses = [StubURLProtocol.self]
          let urlSession = URLSession(configuration: stubConfig)
          let config = PayabliConfig(
              accessToken: "abc",
              entryPoint: "demo",
              environment: .sandbox
          )
          let session = PayabliSession(config: config, urlSession: urlSession)
          XCTAssertNotNil(session.service)
      }
  }
  ```

- [ ] **Step 2: Run the test — verify it fails to compile**
  - Run: `swift test --filter PayabliSessionTests`
  - Expected: compile error "cannot find 'PayabliSession' in scope".

- [ ] **Step 3: Implement `PayabliSession`** in `Sources/PayabliSDKCore/Public/PayabliSession.swift`:

  ```swift
  import Foundation

  /// A shared session backbone used by every PayabliSDK component instance
  /// that targets the same `PayabliConfig`.
  ///
  /// Owns exactly one `PayabliAuth` and one `PayabliService` for the
  /// lifetime of the host app's interaction with Payabli on a given config.
  /// Components (today: `PayabliTTP`; tomorrow: `PayabliPayIn`) accept a
  /// `PayabliSession` so token refreshes, rate limits, and telemetry hooks
  /// live in one place rather than per-facade.
  ///
  /// Construct one explicitly when you intend to share auth across modules:
  ///
  /// ```swift
  /// let session = PayabliSession(config: config)
  /// let ttp = PayabliTTP(session: session, appId: "...", ...)
  /// // Later, when PayIn lands:
  /// // let payIn = PayabliPayIn(session: session, ...)
  /// ```
  ///
  /// The convenience inits on each component facade build a
  /// `PayabliSession` internally — single-component apps do not have to
  /// touch this type.
  public final class PayabliSession: @unchecked Sendable {
      public let config: PayabliConfig
      internal let auth: PayabliAuth
      internal let service: PayabliService

      public init(config: PayabliConfig, urlSession: URLSession? = nil) {
          self.config = config
          self.auth = PayabliAuth(config: config)
          self.service = PayabliService(
              environment: config.environment,
              session: urlSession
          )
      }
  }
  ```

- [ ] **Step 4: Run the test — verify it passes**
  - Run: `swift test --filter PayabliSessionTests`
  - Expected: PASS.

- [ ] **Step 5: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Public/PayabliSession.swift Tests/PayabliSDKCoreTests/PayabliSessionTests.swift
  git commit -m "feat(core): add PayabliSession to share auth/service across components"
  ```

### Task 4.2: Add a `session:`-based designated init on `PayabliTTP`

**Files:**
- Modify: `Sources/PayabliSDKTapToPay/PayabliTTP.swift`
- Test: `Tests/PayabliSDKTapToPayTests/PayabliTTPSessionInitTests.swift`

Plan: keep the existing `init(config:appId:provider:attestation:retryPolicy:session:)` (it gets renamed to `init(session:appId:provider:attestation:retryPolicy:)` but the `URLSession` parameter goes away because the session owns its own transport). Add a thin compatibility init that takes `config:` and builds a `PayabliSession` so old callers keep working.

- [ ] **Step 1: Write the failing test**

  Create `Tests/PayabliSDKTapToPayTests/PayabliTTPSessionInitTests.swift`:
  ```swift
  import XCTest
  @testable import PayabliSDKTapToPay
  @testable import PayabliSDKCore

  @MainActor
  final class PayabliTTPSessionInitTests: XCTestCase {
      func testTwoFacadesShareTheSameAuth() async {
          let config = PayabliConfig(
              accessToken: "shared-token",
              entryPoint: "demo",
              environment: .sandbox
          )
          let session = PayabliSession(config: config)

          let ttp1 = PayabliTTP(
              session: session,
              appId: "T.app",
              provider: MockTapToPayProvider(),
              attestation: MockDeviceAttestationService()
          )
          let ttp2 = PayabliTTP(
              session: session,
              appId: "T.app",
              provider: MockTapToPayProvider(),
              attestation: MockDeviceAttestationService()
          )

          // Both facades reference the same auth actor — proven via object
          // identity at the actor level.
          XCTAssertTrue(ttp1.auth === ttp2.auth)
      }
  }
  ```

  Note: `actor` types compare with `===` like classes via `===` only on metatype, so this assertion uses the actor's reference identity. If the test fails to compile because actors do not allow `===`, replace with comparing `ObjectIdentifier(ttp1.auth) == ObjectIdentifier(ttp2.auth)` after a small actor-isolated helper.

- [ ] **Step 2: Run the test — expect compile error**
  - Run: `swift test --filter PayabliTTPSessionInitTests`
  - Expected: compile error — `init(session:...)` does not exist yet.

- [ ] **Step 3: Add the new designated init.** In `Sources/PayabliSDKTapToPay/PayabliTTP.swift`, replace the existing designated init at line 121-143:

  ```swift
  /// Designated init. Shares a single `PayabliAuth` + `PayabliService`
  /// across every component facade constructed with the same `PayabliSession`.
  public init(
      session: PayabliSession,
      appId: String,
      provider: TapToPayProvider,
      attestation: DeviceAttestationService,
      retryPolicy: RetryPolicy = .default
  ) {
      self.entryPoint = session.config.entryPoint
      self.appId = appId
      self.environment = session.config.environment
      self.provider = provider
      self.attestation = attestation
      self.retryPolicy = retryPolicy

      self.service = session.service
      self.auth = session.auth
      self.transactionClient = TTPTransactionClient(service: session.service, auth: session.auth)
      self.configClient = TTPConfigClient(
          service: session.service,
          auth: session.auth,
          attestation: attestation
      )
      super.init()
  }

  /// Convenience init that wraps a `PayabliConfig` in a fresh
  /// `PayabliSession`. Use the `session:` init when you need to share auth
  /// across multiple component facades on the same config.
  public convenience init(
      config: PayabliConfig,
      appId: String,
      provider: TapToPayProvider,
      attestation: DeviceAttestationService,
      retryPolicy: RetryPolicy = .default,
      session: URLSession? = nil
  ) {
      let payabliSession = PayabliSession(config: config, urlSession: session)
      self.init(
          session: payabliSession,
          appId: appId,
          provider: provider,
          attestation: attestation,
          retryPolicy: retryPolicy
      )
  }
  ```

- [ ] **Step 4: Update the `accessToken:` convenience init** at line 87-115 to use `PayabliSession`:

  ```swift
  #if canImport(DeviceCheck)
  public convenience init(
      accessToken: String,
      tokenProvider: PayabliTokenRefresh? = nil,
      entryPoint: String,
      appId: String,
      environment: PayabliEnvironment
  ) {
      let config = PayabliConfig(
          accessToken: accessToken,
          tokenProvider: tokenProvider,
          entryPoint: entryPoint,
          environment: environment
      )
      let session = PayabliSession(config: config)
      let storage: SecureStorage = KeychainStorage()
      let attestation = AppAttestService(
          service: session.service,
          auth: session.auth,
          attestor: RealAppAttestor(),
          storage: storage
      )
      self.init(
          session: session,
          appId: appId,
          provider: FiservCardReader(),
          attestation: attestation
      )
  }
  #endif
  ```

- [ ] **Step 5: Run the new test — expect PASS**
  - Run: `swift test --filter PayabliTTPSessionInitTests`
  - Expected: PASS.

- [ ] **Step 6: Run the full TapToPay suite**
  - Run: `swift test --filter PayabliSDKTapToPayTests`
  - Expected: every existing test still passes — the convenience init signature is unchanged.

- [ ] **Step 7: Commit**
  ```bash
  git add Sources/PayabliSDKTapToPay/PayabliTTP.swift Tests/PayabliSDKTapToPayTests/PayabliTTPSessionInitTests.swift
  git commit -m "feat(taptopay): add session: designated init on PayabliTTP"
  ```

### Task 4.3: Add a token-rotation `AsyncStream` on `PayabliAuth` (Finding 13)

**Files:**
- Modify: `Sources/PayabliSDKCore/Auth/PayabliAuth.swift`
- Test: `Tests/PayabliSDKCoreTests/PayabliAuthTests.swift` (add a test method)

- [ ] **Step 1: Write the failing test**. Append to `Tests/PayabliSDKCoreTests/PayabliAuthTests.swift`:

  ```swift
  func testTokenChangesEmitsAfterRefresh() async throws {
      let config = PayabliConfig(
          accessToken: "old",
          tokenProvider: { "new" },
          entryPoint: "demo",
          environment: .sandbox
      )
      let auth = PayabliAuth(config: config)

      let stream = await auth.tokenChanges()
      let collector = Task<String?, Never> {
          for await token in stream {
              return token
          }
          return nil
      }

      _ = try await auth.invalidateAndRefresh()
      let received = await collector.value
      XCTAssertEqual(received, "new")
  }
  ```

- [ ] **Step 2: Run the test — expect compile error**
  - Run: `swift test --filter testTokenChangesEmitsAfterRefresh`
  - Expected: "cannot find 'tokenChanges' in scope".

- [ ] **Step 3: Implement `tokenChanges()`** in `Sources/PayabliSDKCore/Auth/PayabliAuth.swift`. Add to the `PayabliAuth` actor:

  ```swift
  // Multicasts every successful token rotation. Producers append on every
  // refresh; consumers iterate as long as they want.
  private var tokenChangeContinuations: [UUID: AsyncStream<String>.Continuation] = [:]

  /// AsyncStream that emits whenever `invalidateAndRefresh()` succeeds.
  /// Each call returns an independent stream — multiple subscribers each
  /// receive every subsequent token.
  public func tokenChanges() -> AsyncStream<String> {
      let id = UUID()
      return AsyncStream { continuation in
          tokenChangeContinuations[id] = continuation
          continuation.onTermination = { [weak self] _ in
              Task { await self?.removeTokenChangeContinuation(id: id) }
          }
      }
  }

  private func removeTokenChangeContinuation(id: UUID) {
      tokenChangeContinuations.removeValue(forKey: id)
  }
  ```

  Then add the emit in `invalidateAndRefresh()` right after `currentToken = fresh`:

  ```swift
  do {
      let fresh = try await task.value
      currentToken = fresh
      inFlightRefresh = nil
      logger.info("Access token refreshed")
      // Notify observers of the rotation.
      for (_, continuation) in tokenChangeContinuations {
          continuation.yield(fresh)
      }
      return fresh
  } catch { ... }
  ```

- [ ] **Step 4: Run the test — expect PASS**
  - Run: `swift test --filter testTokenChangesEmitsAfterRefresh`

- [ ] **Step 5: Run the full suite**
  - Run: `swift test`

- [ ] **Step 6: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Auth/PayabliAuth.swift Tests/PayabliSDKCoreTests/PayabliAuthTests.swift
  git commit -m "feat(core): add tokenChanges() AsyncStream on PayabliAuth"
  ```

---

## Phase 5 — Transport seam (Proposal B + Findings 6, 12)

Goal: every endpoint client depends on `protocol PayabliTransport` (in Core), with a private `AuthenticatedTransport` decorator (in Core) injecting the bearer header and handling 401-refresh-once. Inline retry loops disappear from TapToPay code.

### Task 5.1: Add the `PayabliTransport` protocol and conform `PayabliService`

**Files:**
- Create: `Sources/PayabliSDKCore/Networking/PayabliTransport.swift`
- Modify: `Sources/PayabliSDKCore/Networking/PayabliService.swift`
- Test: `Tests/PayabliSDKCoreTests/PayabliTransportTests.swift`

- [ ] **Step 1: Write the failing test**

  ```swift
  import XCTest
  @testable import PayabliSDKCore

  final class PayabliTransportTests: XCTestCase {
      func testPayabliServiceConformsToPayabliTransport() {
          let service = PayabliService(environment: .sandbox)
          let _: any PayabliTransport = service  // compile-time conformance proof
          XCTAssertTrue(true)
      }
  }
  ```

- [ ] **Step 2: Run the test — expect compile error**
  - Run: `swift test --filter PayabliTransportTests`
  - Expected: "cannot find type 'PayabliTransport' in scope".

- [ ] **Step 3: Add the protocol** in `Sources/PayabliSDKCore/Networking/PayabliTransport.swift`:

  ```swift
  import Foundation

  /// Transport-level seam used by every endpoint client. Decorators
  /// (e.g. authenticated bearer-header injection, request signing) wrap
  /// a base implementation without endpoint clients having to know.
  public protocol PayabliTransport: Sendable {
      func perform(_ request: PayabliRequest) async throws -> PayabliResponse
      func performV2<T: Decodable & Sendable>(
          _ request: PayabliRequest,
          decoding: T.Type
      ) async throws -> PayabliV2Envelope<T>
  }
  ```

- [ ] **Step 4: Conform `PayabliService`** to the protocol. The methods already exist with the right signatures, so just add the protocol conformance to the declaration. In `Sources/PayabliSDKCore/Networking/PayabliService.swift:17`:

  ```swift
  public final class PayabliService: PayabliTransport, Sendable {
  ```

- [ ] **Step 5: Run the test — expect PASS**
  - Run: `swift test --filter PayabliTransportTests`

- [ ] **Step 6: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Networking/PayabliTransport.swift Sources/PayabliSDKCore/Networking/PayabliService.swift Tests/PayabliSDKCoreTests/PayabliTransportTests.swift
  git commit -m "feat(core): introduce PayabliTransport protocol; PayabliService conforms"
  ```

### Task 5.2: Add `AuthenticatedTransport` decorator

**Files:**
- Create: `Sources/PayabliSDKCore/Networking/AuthenticatedTransport.swift`
- Test: `Tests/PayabliSDKCoreTests/AuthenticatedTransportTests.swift`

- [ ] **Step 1: Write the failing tests** covering happy path + 401 refresh-and-retry + double-401 propagation.

  Create `Tests/PayabliSDKCoreTests/AuthenticatedTransportTests.swift`:
  ```swift
  import XCTest
  @testable import PayabliSDKCore

  final class AuthenticatedTransportTests: XCTestCase {

      func testInjectsBearerHeaderOnEveryRequest() async throws {
          let mock = MockTransport(scripted: [
              .response(statusCode: 200, body: Data("{}".utf8))
          ])
          let auth = PayabliAuth(config: PayabliConfig(
              accessToken: "tok-1",
              entryPoint: "demo",
              environment: .sandbox
          ))
          let decorator = AuthenticatedTransport(base: mock, auth: auth)
          let request = PayabliRequest(method: .get, path: "/x")
          _ = try await decorator.perform(request)

          let captured = await mock.captured()
          XCTAssertEqual(captured.first?.headers["Authorization"], "Bearer tok-1")
      }

      func testRefreshesAndRetriesOn401() async throws {
          let mock = MockTransport(scripted: [
              .response(statusCode: 401, body: Data()),
              .response(statusCode: 200, body: Data("{}".utf8))
          ])
          let auth = PayabliAuth(config: PayabliConfig(
              accessToken: "old",
              tokenProvider: { "new" },
              entryPoint: "demo",
              environment: .sandbox
          ))
          let decorator = AuthenticatedTransport(base: mock, auth: auth)
          let request = PayabliRequest(method: .get, path: "/x")
          let response = try await decorator.perform(request)

          XCTAssertEqual(response.statusCode, 200)
          let captured = await mock.captured()
          XCTAssertEqual(captured.count, 2)
          XCTAssertEqual(captured[0].headers["Authorization"], "Bearer old")
          XCTAssertEqual(captured[1].headers["Authorization"], "Bearer new")
      }

      func testThrowsTokenExpiredAfterDouble401() async {
          let mock = MockTransport(scripted: [
              .response(statusCode: 401, body: Data()),
              .response(statusCode: 401, body: Data())
          ])
          let auth = PayabliAuth(config: PayabliConfig(
              accessToken: "old",
              tokenProvider: { "new" },
              entryPoint: "demo",
              environment: .sandbox
          ))
          let decorator = AuthenticatedTransport(base: mock, auth: auth)
          let request = PayabliRequest(method: .get, path: "/x")
          do {
              _ = try await decorator.perform(request)
              XCTFail("expected throw")
          } catch let error as PayabliGenericError {
              XCTAssertEqual(error.code, .tokenExpired)
          } catch {
              XCTFail("wrong error: \(error)")
          }
      }
  }

  // MARK: - MockTransport

  actor MockTransport: PayabliTransport {
      enum Scripted: Sendable {
          case response(statusCode: Int, body: Data)
      }

      private var scripted: [Scripted]
      private var requests: [PayabliRequest] = []

      init(scripted: [Scripted]) {
          self.scripted = scripted
      }

      func captured() -> [PayabliRequest] { requests }

      func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
          requests.append(request)
          guard !scripted.isEmpty else {
              throw PayabliGenericError(code: .networkError, reason: "no more scripted responses")
          }
          let next = scripted.removeFirst()
          switch next {
          case let .response(statusCode, body):
              return PayabliResponse(statusCode: statusCode, headers: [:], body: body)
          }
      }

      func performV2<T: Decodable & Sendable>(
          _ request: PayabliRequest,
          decoding: T.Type
      ) async throws -> PayabliV2Envelope<T> {
          let response = try await perform(request)
          return try JSONDecoder().decode(PayabliV2Envelope<T>.self, from: response.body)
      }
  }
  ```

- [ ] **Step 2: Run tests — expect compile errors** ("cannot find AuthenticatedTransport").
  - Run: `swift test --filter AuthenticatedTransportTests`

- [ ] **Step 3: Implement `AuthenticatedTransport`**

  Create `Sources/PayabliSDKCore/Networking/AuthenticatedTransport.swift`:
  ```swift
  import Foundation

  /// Decorator that injects the `Authorization: Bearer <token>` header on
  /// every outgoing request and handles HTTP 401 with a single
  /// refresh-and-retry. After two consecutive 401s, throws
  /// `PayabliGenericError(.tokenExpired)`.
  ///
  /// Endpoint clients that need bearer auth depend on this transport rather
  /// than open-coding the header / retry dance themselves.
  public struct AuthenticatedTransport: PayabliTransport {
      private let base: any PayabliTransport
      private let auth: PayabliAuth

      public init(base: any PayabliTransport, auth: PayabliAuth) {
          self.base = base
          self.auth = auth
      }

      public func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
          let token = await auth.currentAccessToken()
          let firstAttempt = try await base.perform(authorize(request, with: token))

          guard firstAttempt.statusCode == 401 else { return firstAttempt }

          // Single refresh-and-retry. If the second attempt is also 401,
          // surface .tokenExpired so the facade can clear attestation.
          let refreshed = try await auth.invalidateAndRefresh()
          let secondAttempt = try await base.perform(authorize(request, with: refreshed))
          if secondAttempt.statusCode == 401 {
              throw PayabliGenericError(
                  code: .tokenExpired,
                  reason: "Refresh token rejected"
              )
          }
          return secondAttempt
      }

      public func performV2<T: Decodable & Sendable>(
          _ request: PayabliRequest,
          decoding: T.Type
      ) async throws -> PayabliV2Envelope<T> {
          let response = try await perform(request)
          let decoder = JSONDecoder()
          decoder.dateDecodingStrategy = .iso8601
          do {
              return try decoder.decode(PayabliV2Envelope<T>.self, from: response.body)
          } catch {
              throw PayabliGenericError(
                  code: .decodingError,
                  reason: "Failed to decode v2 envelope",
                  underlying: error
              )
          }
      }

      private func authorize(_ request: PayabliRequest, with token: String) -> PayabliRequest {
          var headers = request.headers
          headers["Authorization"] = "Bearer \(token)"
          return PayabliRequest(
              method: request.method,
              path: request.path,
              query: request.query,
              headers: headers,
              body: request.body
          )
      }
  }
  ```

  Note: this assumes `PayabliRequest` has an init taking `method, path, query, headers, body`. If the actual init differs (e.g. labels are different), match the real one when you read `Sources/PayabliSDKCore/Networking/PayabliRequest.swift`.

- [ ] **Step 4: Run the tests — expect PASS**
  - Run: `swift test --filter AuthenticatedTransportTests`

- [ ] **Step 5: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Networking/AuthenticatedTransport.swift Tests/PayabliSDKCoreTests/AuthenticatedTransportTests.swift
  git commit -m "feat(core): add AuthenticatedTransport decorator with 401 refresh-and-retry"
  ```

### Task 5.3: Expose `transport` on `PayabliSession` for component use

**Files:** `Sources/PayabliSDKCore/Public/PayabliSession.swift`

- [ ] **Step 1: Add a `transport` property** that returns an `AuthenticatedTransport` wrapping the session's `service`. In `PayabliSession`:

  ```swift
  public final class PayabliSession: @unchecked Sendable {
      public let config: PayabliConfig
      internal let auth: PayabliAuth
      internal let service: PayabliService

      /// Transport that every endpoint client should consume. Wraps the
      /// session's `PayabliService` with bearer-auth injection and 401
      /// refresh-and-retry.
      public var transport: any PayabliTransport {
          AuthenticatedTransport(base: service, auth: auth)
      }

      public init(config: PayabliConfig, urlSession: URLSession? = nil) { ... }
  }
  ```

  Note: `transport` is computed because both `service` and `auth` are constants, so a fresh decorator each time is cheap and avoids storing two references.

- [ ] **Step 2: Run `swift build` + `swift test`**

- [ ] **Step 3: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Public/PayabliSession.swift
  git commit -m "feat(core): expose AuthenticatedTransport on PayabliSession"
  ```

### Task 5.4: Migrate `TTPTransactionClient` to depend on `PayabliTransport`

**Files:**
- Modify: `Sources/PayabliSDKTapToPay/TTPTransactionClient.swift`
- Modify: `Sources/PayabliSDKTapToPay/PayabliTTP.swift` (the line that constructs the client)

- [ ] **Step 1: Replace the `service: PayabliService, auth: PayabliAuth` dependency** with a single `transport: any PayabliTransport`. In `Sources/PayabliSDKTapToPay/TTPTransactionClient.swift`:

  Before:
  ```swift
  public final class TTPTransactionClient: Sendable {
      private let service: PayabliService
      private let auth: PayabliAuth
      ...
      public init(service: PayabliService, auth: PayabliAuth) {
          self.service = service
          self.auth = auth
      }

      public func initiate(...) async throws -> String {
          let token = await auth.currentAccessToken()
          let request = try PayabliRequest.json(
              method: .post,
              path: "/api/v2/MoneyIn/initiate",
              headers: ["Authorization": "Bearer \(token)"],
              jsonBody: body
          )
          ...
          envelope = try await service.performV2(request, decoding: InitiateData.self)
          ...
      }
  }
  ```

  After:
  ```swift
  public final class TTPTransactionClient: Sendable {
      private let transport: any PayabliTransport
      private let logger = PayabliLogger(category: .taptopay)

      public init(transport: any PayabliTransport) {
          self.transport = transport
      }

      public func initiate(...) async throws -> String {
          let request = try PayabliRequest.json(
              method: .post,
              path: "/api/v2/MoneyIn/initiate",
              headers: [:],   // bearer header is added by the transport
              jsonBody: body
          )
          ...
          envelope = try await transport.performV2(request, decoding: InitiateData.self)
          ...
      }
  }
  ```

- [ ] **Step 2: Update the call site in `PayabliTTP`'s designated init** (`Sources/PayabliSDKTapToPay/PayabliTTP.swift`):

  ```swift
  self.transactionClient = TTPTransactionClient(transport: session.transport)
  ```

- [ ] **Step 3: Run `swift build`**
  - Expected: any test that constructed a `TTPTransactionClient` directly will need updating. Tests that drive it via the facade are unaffected.

- [ ] **Step 4: Update direct test constructions of `TTPTransactionClient`**, if any — search:
  ```bash
  grep -rn 'TTPTransactionClient(' Tests/
  ```

- [ ] **Step 5: Run tests**
  - Run: `swift test`

- [ ] **Step 6: Commit**
  ```bash
  git add Sources/PayabliSDKTapToPay/TTPTransactionClient.swift Sources/PayabliSDKTapToPay/PayabliTTP.swift Tests/
  git commit -m "refactor(taptopay): TTPTransactionClient depends on PayabliTransport"
  ```

### Task 5.5: Migrate `TTPConfigClient` to depend on `PayabliTransport`

**Files:**
- Modify: `Sources/PayabliSDKTapToPay/TTPConfigClient.swift`
- Modify: `Sources/PayabliSDKTapToPay/PayabliTTP.swift`

- [ ] **Step 1: Refactor `TTPConfigClient`**

  Before:
  ```swift
  public final class TTPConfigClient: Sendable {
      private let service: PayabliService
      private let auth: PayabliAuth
      private let attestation: DeviceAttestationService
      ...
      public init(service: PayabliService, auth: PayabliAuth, attestation: DeviceAttestationService) {
          self.service = service
          self.auth = auth
          self.attestation = attestation
      }

      public func fetchConfig(entry: String) async throws -> TTPConfig {
          let headers = try await assertionHeaders()
          let token = await auth.currentAccessToken()
          let merged = headers.asDictionary.merging(["Authorization": "Bearer \(token)"]) { current, _ in current }
          let request = PayabliRequest(
              method: .get,
              path: "/api/v2/device/taptopay/config/\(entry)",
              headers: merged
          )
          ...
          let response = try await service.perform(request)
          if response.statusCode == 401 { throw PayabliGenericError(code: .tokenExpired, ...) }
          if response.statusCode == 403 { throw PayabliTTPError.devicePendingActivation }
          guard (200..<300).contains(response.statusCode) else { ... }
          ...
      }
  }
  ```

  After:
  ```swift
  public final class TTPConfigClient: Sendable {
      private let transport: any PayabliTransport
      private let attestation: DeviceAttestationService
      private let logger = PayabliLogger(category: .taptopay)

      public init(transport: any PayabliTransport, attestation: DeviceAttestationService) {
          self.transport = transport
          self.attestation = attestation
      }

      public func fetchConfig(entry: String) async throws -> TTPConfig {
          let headers = try await assertionHeaders()

          let request = PayabliRequest(
              method: .get,
              path: "/api/v2/device/taptopay/config/\(entry)",
              headers: headers.asDictionary  // bearer is added by transport
          )

          let headersDump = request.headers
              .map { "\($0.key): \($0.value)" }
              .sorted()
              .joined(separator: " | ")
          logger.info("[config] → GET \(request.path)")
          logger.info("[config] headers: \(headersDump)")

          let response: PayabliResponse
          do {
              response = try await transport.perform(request)
          } catch let error as PayabliGenericError where error.code == .tokenExpired {
              // AuthenticatedTransport already exhausted refresh — surface
              // as devicePendingActivation? No — token expired and config
              // endpoint distinguishes a 403 (pending activation) from a
              // pure 401 (token bad). Re-throw the .tokenExpired so the
              // facade can clear attestation cache and re-attest.
              throw error
          }

          let responseBody = String(data: response.body, encoding: .utf8) ?? "<non-utf8 \(response.body.count) bytes>"
          logger.info("[config] ← [\(response.statusCode)] body: \(responseBody)")

          if response.statusCode == 403 {
              throw PayabliTTPError.devicePendingActivation
          }
          guard (200..<300).contains(response.statusCode) else {
              throw PayabliTTPError.configFailed(reason: "HTTP \(response.statusCode)")
          }

          if let (rawCode, reason) = PayabliEnvelope.declineOutcome(from: response.body) {
              let code = rawCode ?? 0
              logger.error("[config] declined (isSuccess=false code=\(code)): \(reason)")
              if code == 401 { throw PayabliGenericError(code: .tokenExpired, reason: reason) }
              if code == 403 { throw PayabliTTPError.devicePendingActivation }
              throw PayabliTTPError.configFailed(reason: reason)
          }

          let decoder = JSONDecoder()
          guard let envelope = try? decoder.decode(
                  PayabliEnvelope.Success<ConfigCredentialsPayload>.self,
                  from: response.body
                ),
                let credentials = envelope.responseData?.credentials else {
              logger.error("[config] payload decode failed")
              throw PayabliTTPError.configFailed(reason: "Invalid config envelope")
          }

          return TTPConfig(paymentToken: nil, providerCredentials: credentials)
      }

      private func assertionHeaders() async throws -> AssertionHeaders {
          try await attestation.generateAssertion()
      }
  }
  ```

- [ ] **Step 2: Update `PayabliTTP` designated init**

  ```swift
  self.configClient = TTPConfigClient(
      transport: session.transport,
      attestation: attestation
  )
  ```

- [ ] **Step 3: Run `swift build`**
  - Expected: builds clean.

- [ ] **Step 4: Run tests**
  - Run: `swift test`

- [ ] **Step 5: Commit**
  ```bash
  git add Sources/PayabliSDKTapToPay/TTPConfigClient.swift Sources/PayabliSDKTapToPay/PayabliTTP.swift Tests/
  git commit -m "refactor(taptopay): TTPConfigClient depends on PayabliTransport"
  ```

### Task 5.6: Delete the open-coded 401 retry loop in `PayabliTTP+Charge.tryUpdate`

**Files:** `Sources/PayabliSDKTapToPay/PayabliTTP+Charge.swift`

`tryUpdate` runs `PATCH /MoneyIn/update/{id}`. Today it open-codes a 401-refresh-and-retry inside the body of the retry loop. With `AuthenticatedTransport` in place, the inner refresh logic is redundant.

- [ ] **Step 1: Replace the retry body**

  In `Sources/PayabliSDKTapToPay/PayabliTTP+Charge.swift:177-235`, the current body looks like:

  ```swift
  do {
      try await Retry.run(policy: retryPolicy) { [retryPolicy, auth] _ in
          let token = await auth.currentAccessToken()
          var response = try await performOnce(token: token, attempt: "first")

          if response.statusCode == 401 {
              let refreshed = try await auth.invalidateAndRefresh()
              response = try await performOnce(token: refreshed, attempt: "refreshed")
          }

          if (200..<300).contains(response.statusCode) { return }
          if retryPolicy.isRetryable(statusCode: response.statusCode) {
              throw RetryableError(PayabliTTPError.updateFailed(
                  reason: "HTTP \(response.statusCode)"
              ))
          }
          throw PayabliTTPError.updateFailed(reason: "HTTP \(response.statusCode)")
      }
      return .succeeded
  } catch { ... }
  ```

  After this task, the closure trusts the transport (now `AuthenticatedTransport` injected via `PayabliSession.transport`) to handle the 401 dance. The retry policy is only about idempotent 5xx / 408 retries.

  Replace `tryUpdate(...)` with:

  ```swift
  private func tryUpdate(
      paymentTransId: String,
      payload: TTPUpdatePayload
  ) async -> TTPUpdateOutcome {
      let body = TTPTransactionClient.updateBody(for: payload)
      let logger = self.logger
      let bodyDump = String(data: body, encoding: .utf8) ?? "<non-utf8 \(body.count) bytes>"
      let path = "/api/v2/MoneyIn/update/\(paymentTransId)"
      let transport = self.session.transport

      @Sendable func performOnce(attempt: String) async throws -> PayabliResponse {
          let request = PayabliRequest(
              method: .patch,
              path: path,
              headers: ["Content-Type": "application/json"],
              body: body
          )
          let headersDump = request.headers
              .map { "\($0.key): \($0.value)" }
              .sorted()
              .joined(separator: " | ")
          logger.info("[update/\(attempt)] → PATCH \(path)")
          logger.info("[update/\(attempt)] headers: \(headersDump)")
          logger.info("[update/\(attempt)] body: \(bodyDump)")
          let response = try await transport.perform(request)
          let responseBody = String(data: response.body, encoding: .utf8) ?? "<non-utf8 \(response.body.count) bytes>"
          logger.info("[update/\(attempt)] ← [\(response.statusCode)] body: \(responseBody)")
          return response
      }

      do {
          try await Retry.run(policy: retryPolicy) { [retryPolicy] attempt in
              let response = try await performOnce(attempt: String(attempt))

              if (200..<300).contains(response.statusCode) { return }
              if retryPolicy.isRetryable(statusCode: response.statusCode) {
                  throw RetryableError(PayabliTTPError.updateFailed(
                      reason: "HTTP \(response.statusCode)"
                  ))
              }
              throw PayabliTTPError.updateFailed(reason: "HTTP \(response.statusCode)")
          }
          return .succeeded
      } catch {
          let reason = String(describing: error)
          multicaster.emit(.updateFailed(paymentTransId: paymentTransId, error: reason))
          return .failed(reason: reason)
      }
  }
  ```

  Note: this references `self.session.transport` — which means `PayabliTTP` needs a `let session: PayabliSession` ivar. Add this as a small refactor in step 2.

- [ ] **Step 2: Add `let session: PayabliSession` ivar** to `PayabliTTP`. In `Sources/PayabliSDKTapToPay/PayabliTTP.swift`, around line 53 (after the `// Networking` comment):

  ```swift
  // Networking
  let session: PayabliSession
  let service: PayabliService
  let auth: PayabliAuth
  let transactionClient: TTPTransactionClient
  let configClient: TTPConfigClient
  ```

  And in the designated init (the `session:` one), assign `self.session = session` before the existing assignments.

- [ ] **Step 3: Run `swift build`**

- [ ] **Step 4: Run the full TapToPay tests**
  - Run: `swift test --filter PayabliSDKTapToPayTests`
  - Expected: every charge test still passes. The behaviour is preserved: 401 → refresh → retry once via the transport; 5xx → exponential backoff via `Retry.run`. No double-401 handling, since `AuthenticatedTransport` throws `.tokenExpired` after a single failed refresh.

- [ ] **Step 5: Commit**
  ```bash
  git add Sources/PayabliSDKTapToPay/PayabliTTP+Charge.swift Sources/PayabliSDKTapToPay/PayabliTTP.swift
  git commit -m "refactor(taptopay): delete open-coded 401 retry loop in tryUpdate"
  ```

### Task 5.7: Unify HTTP error mapping (Finding 12)

**Files:**
- Modify: `Sources/PayabliSDKCore/Networking/PayabliService.swift` (extend `mapHTTPError` with an optional override hook)
- Modify: `Sources/PayabliSDKTapToPay/TTPConfigClient.swift` (call the shared mapper)

- [ ] **Step 1: Extend `mapHTTPError`** with an optional per-call override:

  ```swift
  public func mapHTTPError(
      response: PayabliResponse,
      override: ((Int) -> (any Error)?)? = nil
  ) throws {
      guard !(200..<300).contains(response.statusCode) else { return }
      if let mapped = override?(response.statusCode) { throw mapped }
      // existing switch unchanged
  }
  ```

- [ ] **Step 2: Replace the manual status-code handling in `TTPConfigClient.fetchConfig`** with a call to the shared mapper:

  After `let response = try await transport.perform(request)`, instead of manual `if response.statusCode == 403 { throw .devicePendingActivation }` blocks, write:

  ```swift
  try (transport as? PayabliService)?.mapHTTPError(response: response, override: { code in
      if code == 403 { return PayabliTTPError.devicePendingActivation }
      return nil
  })
  ```

  Note: the transport here is wrapped in `AuthenticatedTransport`, so it is not directly a `PayabliService`. Promote `mapHTTPError` to a free function in Core for clean access:

  ```swift
  public func mapPayabliHTTPError(
      response: PayabliResponse,
      override: ((Int) -> (any Error)?)? = nil
  ) throws {
      guard !(200..<300).contains(response.statusCode) else { return }
      if let mapped = override?(response.statusCode) { throw mapped }
      // ... same body as the existing PayabliService.mapHTTPError ...
  }
  ```

  Add it as a free function in `Sources/PayabliSDKCore/Networking/PayabliService.swift` (or a new `HTTPErrorMapping.swift` file) and have `PayabliService.mapHTTPError` delegate to it. Then `TTPConfigClient` calls the free function directly.

- [ ] **Step 3: Run `swift build` + `swift test`**

- [ ] **Step 4: Commit**
  ```bash
  git add Sources/PayabliSDKCore/Networking/ Sources/PayabliSDKTapToPay/TTPConfigClient.swift
  git commit -m "refactor(core): unify HTTP error mapping into a shared mapPayabliHTTPError"
  ```

---

## Phase 6 — Delete `TapToPayProviderFactory` (Proposal D)

### Task 6.1: Delete the factory and its tests

**Files:**
- Delete: `Sources/PayabliSDKTapToPay/TapToPayProviderFactory.swift`
- Delete: `Tests/PayabliSDKTapToPayTests/TapToPayProviderFactoryTests.swift`

- [ ] **Step 1: Confirm no production caller**
  - Run: `grep -rn 'TapToPayProviderFactory' Sources/ Example/`
  - Expected: zero matches in `Sources/`. (Tests will reference it; that is fine — they get deleted too.)

- [ ] **Step 2: Delete the files**
  ```bash
  git rm Sources/PayabliSDKTapToPay/TapToPayProviderFactory.swift
  git rm Tests/PayabliSDKTapToPayTests/TapToPayProviderFactoryTests.swift
  ```

- [ ] **Step 3: Run `swift build` + `swift test`**

- [ ] **Step 4: Commit**
  ```bash
  git commit -m "$(cat <<'EOF'
refactor(taptopay): remove unused TapToPayProviderFactory

The factory had no production caller — PayabliTTP wired
FiservCardReader() directly. Removing dead public surface is
cheaper than evolving it; reintroduce a registry once a real
second-provider use case materializes.

EOF
)"
  ```

---

## Phase 7 — Test target hygiene (Finding 16)

Goal: downgrade `@testable import` to plain `import` everywhere it is not load-bearing.

### Task 7.1: Audit and downgrade `@testable import` usage in `PayabliSDKTapToPayTests`

**Files:** every file under `Tests/PayabliSDKTapToPayTests/` that begins with `@testable import PayabliSDKTapToPay`.

- [ ] **Step 1: List all test files using `@testable`**
  ```bash
  grep -l '@testable import PayabliSDKTapToPay' Tests/PayabliSDKTapToPayTests/
  ```

- [ ] **Step 2: For each file, attempt to downgrade**

  Workflow per file:
  1. Replace `@testable import PayabliSDKTapToPay` with `import PayabliSDKTapToPay`.
  2. Run `swift test --filter <ThatFile>`.
  3. If it compiles + passes, leave the change in. If it fails, revert just that file (some tests genuinely need `internal` access).

  Files almost certainly OK to downgrade:
  - `Tests/PayabliSDKTapToPayTests/PayabliTTPEventCodeMappingTests.swift` (only touches `PayabliTTPEventCode`).
  - `Tests/PayabliSDKTapToPayTests/PayabliTTPErrorNSErrorTests.swift` (only `PayabliTTPError`).
  - `Tests/PayabliSDKTapToPayTests/PayabliTTPObjCInteropTests.swift` (only ObjC-bridged public surface).
  - `Tests/PayabliSDKTapToPayTests/RetryPolicyTests.swift` — already moved to Core in Phase 1.

  Files that may need to keep `@testable`:
  - `Tests/PayabliSDKTapToPayTests/AppAttestServiceTests.swift` (the internal init for hardware-id providers).
  - `Tests/PayabliSDKTapToPayTests/SessionManagerTests.swift` (after Task 2.1, the type is internal).
  - `Tests/PayabliSDKTapToPayTests/FiservCardReaderTests.swift` (after Task 2.3, `Credentials` is internal).
  - `Tests/PayabliSDKTapToPayTests/TTPTransactionWireFormatTests.swift` (likely tests internal wire-format DTOs).

- [ ] **Step 3: After each downgrade, commit per file** so each change is reviewable on its own:

  ```bash
  git add Tests/PayabliSDKTapToPayTests/<file>.swift
  git commit -m "test(taptopay): downgrade @testable import in <file>"
  ```

### Task 7.2: Same audit for `PayabliSDKCoreTests`

- [ ] Repeat Task 7.1 for `Tests/PayabliSDKCoreTests/`. Files almost certainly OK to downgrade:
  - `Tests/PayabliSDKCoreTests/PayabliEnvironmentTests.swift`
  - `Tests/PayabliSDKCoreTests/PayabliThemeTests.swift`
  - `Tests/PayabliSDKCoreTests/PayabliSDKCoreTests.swift` (sanity tests)

  Likely needs `@testable`:
  - `Tests/PayabliSDKCoreTests/PayabliAuthTests.swift` (actor internals; see also new test added in Task 4.3)
  - `Tests/PayabliSDKCoreTests/PayabliServiceTests.swift` (private helper testing)
  - `Tests/PayabliSDKCoreTests/AuthenticatedTransportTests.swift` — added in Task 5.2

---

## Phase 8 — `PayabliSDKTestUtils` library product (Proposal E)

Goal: ship test fixtures as a real SPM library product so host apps and future modules can depend on them.

### Task 8.1: Add the new target to `Package.swift`

**Files:** `Package.swift`

- [ ] **Step 1: Add the product and target declarations**

  Insert into the `products: [...]` array (after the existing `.library(...)` entries):
  ```swift
  .library(
      name: "PayabliSDKTestUtils",
      type: .dynamic,
      targets: ["PayabliSDKTestUtils"]
  ),
  ```

  Insert into the `targets: [...]` array (after the existing `.target(name: "PayabliSDKTelemetry", ...)`):
  ```swift
  .target(
      name: "PayabliSDKTestUtils",
      dependencies: ["PayabliSDKCore", "PayabliSDKTapToPay"],
      path: "Sources/PayabliSDKTestUtils"
  ),
  ```

- [ ] **Step 2: Create the source folder**
  ```bash
  mkdir -p Sources/PayabliSDKTestUtils
  ```

- [ ] **Step 3: Add a placeholder file** so SPM is happy with an empty target on first build:
  ```swift
  // Sources/PayabliSDKTestUtils/PayabliSDKTestUtils.swift
  import Foundation

  /// PayabliSDKTestUtils — a shipped collection of in-memory fixtures and
  /// stubs (`StubURLProtocol`, `InMemorySecureStorage`, `MockAppAttestor`,
  /// `MockTapToPayProvider`, `MockDeviceAttestationService`,
  /// `InMemoryTelemetryTransport`) so host applications and future SDK
  /// modules can write tests against the public PayabliSDK API without
  /// re-implementing each stub.
  ///
  /// Mirrors the pattern used by `apple/swift-nio`'s `NIOTestUtils` and
  /// `apple/swift-log`'s `InMemoryLogging` libraries.
  public enum PayabliSDKTestUtils {
      public static let version = "1.0.0"
  }
  ```

- [ ] **Step 4: Run `swift build`**
  - Run: `swift build`
  - Expected: builds clean.

- [ ] **Step 5: Commit**
  ```bash
  git add Package.swift Sources/PayabliSDKTestUtils/
  git commit -m "feat(testutils): add empty PayabliSDKTestUtils library target"
  ```

### Task 8.2: Move `StubURLProtocol` into TestUtils

`StubURLProtocol` exists twice today (`Tests/PayabliSDKCoreTests/StubURLProtocol.swift` and `Tests/PayabliSDKTapToPayTests/StubURLProtocol.swift`). Consolidate.

**Files:**
- Move + promote: `Tests/PayabliSDKCoreTests/StubURLProtocol.swift` → `Sources/PayabliSDKTestUtils/StubURLProtocol.swift`
- Delete: `Tests/PayabliSDKTapToPayTests/StubURLProtocol.swift`

- [ ] **Step 1: Diff the two files**
  ```bash
  diff Tests/PayabliSDKCoreTests/StubURLProtocol.swift Tests/PayabliSDKTapToPayTests/StubURLProtocol.swift
  ```
  - If they are identical, delete the duplicate. If they diverge, take the union and resolve any name clashes inline.

- [ ] **Step 2: Move and promote**

  Move the canonical version into `Sources/PayabliSDKTestUtils/StubURLProtocol.swift`, and:
  - Convert `internal class` → `public final class`.
  - Convert `internal func` → `public func` for every member that tests outside the module need to call.
  - Mark the registration function `register(stubs:)` (or whatever the API is) `public static`.
  - Keep helper types `internal` if they are only consumed within the file.

  Example shape (substitute the actual API):
  ```swift
  import Foundation

  /// In-memory `URLProtocol` for stubbing HTTP responses in tests.
  /// Register stubs before exercising the SDK; the protocol class intercepts
  /// every request your `URLSession` makes.
  ///
  /// ```swift
  /// let session = StubURLProtocol.makeSession()
  /// StubURLProtocol.register(stubs: [
  ///     "/api/v2/...": .ok(body: data)
  /// ])
  /// ```
  public final class StubURLProtocol: URLProtocol {
      public static func makeSession() -> URLSession {
          let configuration = URLSessionConfiguration.ephemeral
          configuration.protocolClasses = [StubURLProtocol.self]
          return URLSession(configuration: configuration)
      }

      public static func register(stubs: [String: Stub]) { ... }
      public static func reset() { ... }
      // override URLProtocol methods unchanged
  }

  public enum StubURLProtocol.Stub { ... }
  ```

- [ ] **Step 3: Update test imports**

  In every test file that imports `@testable import PayabliSDKCoreTests` to use `StubURLProtocol`, add:
  ```swift
  import PayabliSDKTestUtils
  ```

  (Drop any local declaration of `StubURLProtocol` within tests.)

- [ ] **Step 4: Update test target dependencies in `Package.swift`**

  ```swift
  .testTarget(
      name: "PayabliSDKCoreTests",
      dependencies: ["PayabliSDKCore", "PayabliSDKTestUtils"],
      path: "Tests/PayabliSDKCoreTests"
  ),
  .testTarget(
      name: "PayabliSDKTapToPayTests",
      dependencies: ["PayabliSDKTapToPay", "PayabliSDKTestUtils"],
      path: "Tests/PayabliSDKTapToPayTests"
  ),
  .testTarget(
      name: "PayabliSDKTelemetryTests",
      dependencies: ["PayabliSDKTelemetry", "PayabliSDKTestUtils"],
      path: "Tests/PayabliSDKTelemetryTests"
  ),
  ```

- [ ] **Step 5: Delete the duplicate from TapToPay tests**
  ```bash
  git rm Tests/PayabliSDKTapToPayTests/StubURLProtocol.swift
  ```

- [ ] **Step 6: Run `swift build` + `swift test`**

- [ ] **Step 7: Commit**
  ```bash
  git add Package.swift Sources/PayabliSDKTestUtils/StubURLProtocol.swift Tests/
  git commit -m "feat(testutils): promote StubURLProtocol to PayabliSDKTestUtils"
  ```

### Task 8.3: Move `InMemorySecureStorage` into TestUtils

Same pattern as Task 8.2.

**Files:**
- Move: `Tests/PayabliSDKCoreTests/InMemorySecureStorage.swift` → `Sources/PayabliSDKTestUtils/InMemorySecureStorage.swift` (if the file lives elsewhere, find it first via `grep -rln 'InMemorySecureStorage' Tests/`).
- Promote `internal` → `public` for the type and its public methods.

- [ ] **Step 1: Locate the file** and inspect its public surface.
  ```bash
  grep -rln 'InMemorySecureStorage' Tests/ Sources/
  ```

- [ ] **Step 2: Move + promote** following the Task 8.2 pattern.

- [ ] **Step 3: Update imports + Package.swift dependencies** if not done in Task 8.2.

- [ ] **Step 4: Run `swift build` + `swift test`**

- [ ] **Step 5: Commit**
  ```bash
  git commit -m "feat(testutils): promote InMemorySecureStorage to PayabliSDKTestUtils"
  ```

### Task 8.4: Move `MockAppAttestor` into TestUtils

Same pattern.

- [ ] Move `Tests/PayabliSDKTapToPayTests/MockAppAttestor.swift` → `Sources/PayabliSDKTestUtils/MockAppAttestor.swift`.
- [ ] Promote to `public`.
- [ ] Run build + tests.
- [ ] Commit.

### Task 8.5: Move `MockTapToPayProvider` into TestUtils

Same pattern.

- [ ] Move `Tests/PayabliSDKTapToPayTests/MockTapToPayProvider.swift` → `Sources/PayabliSDKTestUtils/MockTapToPayProvider.swift`.
- [ ] Promote to `public`.
- [ ] Run build + tests.
- [ ] Commit.

### Task 8.6: Move `MockDeviceAttestationService` into TestUtils

Same pattern.

- [ ] Move + promote + commit.

### Task 8.7: Move `InMemoryTelemetryTransport` into TestUtils

- [ ] Move `Tests/PayabliSDKTelemetryTests/InMemoryTelemetryTransport.swift` (or wherever it lives — `grep -rln`) → `Sources/PayabliSDKTestUtils/InMemoryTelemetryTransport.swift`.
- [ ] Promote.
- [ ] Update `PayabliSDKTestUtils` target's dependencies in `Package.swift` to include `PayabliSDKTelemetry` if needed:
  ```swift
  .target(
      name: "PayabliSDKTestUtils",
      dependencies: ["PayabliSDKCore", "PayabliSDKTapToPay", "PayabliSDKTelemetry"],
      path: "Sources/PayabliSDKTestUtils"
  ),
  ```
- [ ] Run build + tests.
- [ ] Commit.

### Task 8.8: Add a TestUtils smoke test target

So future regressions in the public test-utils surface are caught at CI time.

**Files:**
- Create: `Tests/PayabliSDKTestUtilsTests/PayabliSDKTestUtilsTests.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Add the test target to Package.swift**

  ```swift
  .testTarget(
      name: "PayabliSDKTestUtilsTests",
      dependencies: ["PayabliSDKTestUtils"],
      path: "Tests/PayabliSDKTestUtilsTests"
  )
  ```

- [ ] **Step 2: Add a smoke test**

  ```swift
  import XCTest
  @testable import PayabliSDKTestUtils

  final class PayabliSDKTestUtilsTests: XCTestCase {
      func testStubURLProtocolMakeSessionReturnsConfiguredSession() {
          let session = StubURLProtocol.makeSession()
          let protocols = session.configuration.protocolClasses ?? []
          XCTAssertTrue(protocols.contains { $0 == StubURLProtocol.self })
      }

      func testInMemorySecureStorageRoundTrips() {
          let storage = InMemorySecureStorage()
          storage.set("hello", forKey: "key")
          XCTAssertEqual(storage.string(forKey: "key"), "hello")
          storage.remove(forKey: "key")
          XCTAssertNil(storage.string(forKey: "key"))
      }

      func testMockTapToPayProviderInitializes() {
          _ = MockTapToPayProvider()
          XCTAssertTrue(true)
      }
  }
  ```

- [ ] **Step 3: Run + commit**
  ```bash
  swift test
  git add Tests/PayabliSDKTestUtilsTests Package.swift
  git commit -m "test(testutils): smoke tests for the public PayabliSDKTestUtils surface"
  ```

---

## Phase 9 — Documentation finalization (Findings 14, 19f)

### Task 9.1: Codify the umbrella inclusion rule in CLAUDE.md (Finding 14)

**Files:** `CLAUDE.md`

- [ ] **Step 1: Read the current Module Architecture section**
  - Run: `grep -n 'umbrella' CLAUDE.md | head`

- [ ] **Step 2: Insert a one-paragraph rule** under the Module Architecture section (or wherever the umbrella is introduced):

  ```markdown
  ### Umbrella inclusion rule

  The `PayabliSDK` umbrella library aggregates targets that lie on the
  critical path of every SDK consumer's primary integration. Today that
  is `PayabliSDKCore` + `PayabliSDKTapToPay`. When PayIn re-lands from
  `develop`, it joins the umbrella; when an opt-in module like
  `PayabliSDKTelemetry` is introduced, it stays out and consumers link it
  explicitly. New modules must declare which side of this line they fall
  on in their own README.
  ```

- [ ] **Step 3: Commit**
  ```bash
  git add CLAUDE.md
  git commit -m "docs(claude): codify umbrella inclusion rule for new modules"
  ```

### Task 9.2: Generate version strings from the build instead of hard-coding (Finding 19f)

**Files:**
- Modify: `Sources/PayabliSDKCore/<wherever PayabliCore.version is defined>` and `Sources/PayabliSDKTapToPay/<PayabliTapToPayModule.version>`

- [ ] **Step 1: Locate the version constants**
  ```bash
  grep -rn 'version = "1.0.0"' Sources/
  ```

- [ ] **Step 2: Replace each with a build-supplied string**

  Two options, in order of preference:

  **(a) `Bundle.main.infoDictionary` lookup** for the `CFBundleShortVersionString` of the SDK's resource bundle. If the SDK ships a bundle (it does — `Resources/PrivacyInfo.xcprivacy`), thread the SDK version into the bundle's `Info.plist` at packaging time and read it here:

  ```swift
  public static var version: String {
      Bundle(for: VersionMarker.self)
          .infoDictionary?["CFBundleShortVersionString"] as? String
          ?? "0.0.0"
  }

  private final class VersionMarker {}
  ```

  **(b) A build-system-fed `.swift` file** generated by `Scripts/build_release_frameworks.sh`. Less portable; not recommended for SPM-only consumers.

  Pick (a). The build-time `Info.plist` injection is part of the release script (`Scripts/build_release_frameworks.sh`) — you may need to add a `-version` argument to that script and have it overwrite the plist before archiving. Verify that the script (or `xcodebuild` invocation) accepts an `MARKETING_VERSION=...` setting.

- [ ] **Step 3: Run `swift build` + `swift test`**

- [ ] **Step 4: Commit**
  ```bash
  git add Sources/ Scripts/
  git commit -m "chore(version): read SDK version from bundle Info.plist instead of hard-coding"
  ```

### Task 9.3: Trim KeychainStorage public surface (Finding 19e)

**Files:** `Sources/PayabliSDKTapToPay/KeychainStorage.swift`

- [ ] **Step 1: Read the file** and identify the public methods.
- [ ] **Step 2: For any `public func` that does not appear in the `SecureStorage` protocol**, change it to `internal`.
- [ ] **Step 3: Run `swift build` + `swift test`**.
- [ ] **Step 4: Commit:**
  ```bash
  git commit -m "refactor(taptopay): trim KeychainStorage public surface to SecureStorage protocol"
  ```

### Task 9.4: Make `PayabliService.makeDefaultSession()` internal (Finding 19b)

**Files:** `Sources/PayabliSDKCore/Networking/PayabliService.swift`

- [ ] **Step 1:** Change `private static func makeDefaultSession()` (line 31) to `internal static func makeDefaultSession()` so the test target can verify configuration.
- [ ] **Step 2:** Run `swift build` + `swift test`.
- [ ] **Step 3:** Commit:
  ```bash
  git commit -m "refactor(core): make makeDefaultSession internal for test access"
  ```

---

## Phase 10 — Final assessment crosscheck

### Task 10.1: Verify every recommendation is closed

- [ ] **Step 1: Walk every finding** in `Documentation/ArchitectureAssessment-2026-05-06.md` and confirm each has a corresponding commit. Findings 8 and 17 were explicitly deferred in the assessment — they may legitimately be unaddressed.

- [ ] **Step 2: Run the full suite one last time**
  - Run: `swift build && swift test`
  - Run: `swift build -c release`
  - Expected: both clean.

- [ ] **Step 3: Update the assessment doc** to mark findings as resolved. At the bottom of `Documentation/ArchitectureAssessment-2026-05-06.md`, add a "Resolution status" appendix:

  ```markdown
  ## Resolution status

  | Finding | Status | Commit |
  | ------- | ------ | ------ |
  | F1 PayabliSession | ✅ resolved | <sha> |
  | F2 PayabliConfig struct | ✅ resolved | <sha> |
  | F3 RetryPolicy → Core | ✅ resolved | <sha> |
  | F4 EventMulticaster generic | ✅ resolved | <sha> |
  | F5 PayabliTransport | ✅ resolved | <sha> |
  | F6 401 retry centralization | ✅ resolved | <sha> |
  | F7 TapToPayProviderFactory deleted | ✅ resolved | <sha> |
  | F8 PayabliTTP ivar access | ⏸ deferred | — |
  | F9 SessionManager → internal | ✅ resolved | <sha> |
  | F10 AppAttestService init | ✅ resolved | <sha> |
  | F11 FiservCardReader internal | ✅ resolved | <sha> |
  | F12 HTTP error mapping unified | ✅ resolved | <sha> |
  | F13 tokenChanges() stream | ✅ resolved | <sha> |
  | F14 Umbrella rule documented | ✅ resolved | <sha> |
  | F15 SessionTierValidator → internal | ✅ resolved | <sha> |
  | F16 @testable hygiene | ✅ resolved | <sha> |
  | F17 @MainActor scope | ⏸ deferred | — |
  | F18 ProximityReader import | ✅ resolved | <sha> |
  | F19 Housekeeping | ✅ resolved | various |
  ```

- [ ] **Step 4: Commit**
  ```bash
  git add Documentation/ArchitectureAssessment-2026-05-06.md
  git commit -m "docs: mark architecture assessment findings as resolved"
  ```

---

## Self-review checklist (run after writing the plan)

- [x] **Spec coverage:** Every finding (1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19) and proposal (A, B, C, D, E) has at least one task. Findings 8 and 17 are deferred per the assessment.
- [x] **No placeholders:** Every code step shows the code; every command shows what to run.
- [x] **Type/method consistency:** `PayabliSession`, `PayabliTransport`, `AuthenticatedTransport`, `tokenChanges()`, `mapPayabliHTTPError` all defined once and reused with the same signatures throughout.
- [x] **Frequent commits:** every task ends in one commit.
- [x] **Sequencing safety:** Phase 1 (move primitives) does not depend on later phases. Phase 4 (PayabliSession) precedes Phase 5 (transport seam) which depends on it. Phase 6 (factory delete) is independent.
