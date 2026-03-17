# PayabliTTP iOS SDK

Accept **Tap to Pay on iPhone** payments with a three-line integration.

```swift
let ttp = PayabliTTP(apiKey: "pk_live_xxx", entry: "entry3715", deviceId: "dev_abc123")
try await ttp.initialize()
let result = try await ttp.charge(amount: 25.00, type: .sale)
```

---

## Requirements

| Requirement | Minimum |
|---|---|
| iOS | 16.7+ |
| Xcode | 15+ |
| Swift | 5.9+ |
| Device | iPhone with NFC (iPhone XS or later) |
| Entitlement | `com.apple.developer.proximity-reader.payment.acceptance` |

> **Device registration required.** The `deviceId` must be pre-registered in the [Payabli dashboard](https://dashboard.payabli.com) before initializing the SDK.

---

## Installation

### Swift Package Manager

Add the package in Xcode via **File → Add Package Dependencies** and enter:

```
https://github.com/payabli/sdk-ios.git
```

Or add it manually to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/payabli/sdk-ios.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["PayabliTTP"]
    )
]
```

---

## Quick Start

### 1. Configure entitlement

Add the following to your app's `.entitlements` file:

```xml
<key>com.apple.developer.proximity-reader.payment.acceptance</key>
<true/>
```

> To obtain this entitlement, request it at [developer.apple.com/contact/request/tap-to-pay-on-iphone](https://developer.apple.com/contact/request/tap-to-pay-on-iphone/). Contact your Payabli account representative for onboarding assistance.

### 2. Initialize the SDK

```swift
import PayabliTTP

let ttp = PayabliTTP(
    apiKey: "pk_live_xxx",       // Payabli publishable key
    entry: "entry3715",           // Payabli entrypoint ID
    deviceId: "dev_abc123",       // Pre-registered device ID
    environment: .production,     // .qa / .sandbox / .production
    logLevel: .info               // .none / .error / .info / .debug
)

try await ttp.initialize()
```

### 3. Accept a payment

```swift
let result = try await ttp.charge(
    amount: 25.00,
    type: .sale,
    order: OrderDetails(orderId: "ORD-001", description: "Coffee"),
    customer: CustomerData(firstName: "John", lastName: "Doe"),
    invoice: InvoiceData(
        invoiceNumber: "INV-001",
        items: [
            LineItem(name: "Espresso", amount: 5.00, quantity: 2),
            LineItem(name: "Muffin", amount: 15.00, quantity: 1)
        ]
    ),
    serviceFee: 1.50
)

print(result.transactionId)   // Payabli transaction ID
print(result.syncStatus)      // .synced | .pendingSyncWithBackend
```

### 4. Observe events (optional)

```swift
for await event in ttp.events {
    switch event {
    case .waitingForCardTap:              showTapUI()
    case .cardTapCompleted:               showProcessingUI()
    case .transactionCompleted(let id):   showSuccess(id)
    case .transactionFailed(let error):   showError(error)
    default: break
    }
}
```

---

## SwiftUI Integration

```swift
struct PaymentView: View {
    @StateObject private var ttp = PayabliTTP(
        apiKey: "pk_live_xxx",
        entry: "entry3715",
        deviceId: "dev_abc123"
    )

    var body: some View {
        VStack {
            if ttp.isReady {
                Button("Charge $25.00") {
                    Task { try await charge() }
                }
            } else {
                ProgressView("Initializing...")
            }
        }
        .task { try? await ttp.initialize() }
    }

    func charge() async throws {
        let result = try await ttp.charge(amount: 25.00, type: .sale)
        print("Transaction:", result.transactionId)
    }
}
```

---

## API Reference

### Constructor

| Parameter | Type | Required | Description |
|---|---|---|---|
| `apiKey` | `String` | ✅ | Payabli publishable key |
| `entry` | `String` | ✅ | Payabli entrypoint ID |
| `deviceId` | `String` | ✅ | Pre-registered device ID |
| `environment` | `PayabliTTPEnvironment` | Default: `.production` | `.qa` / `.sandbox` / `.production` |
| `logLevel` | `LogLevel` | Default: `.none` | `.none` / `.error` / `.info` / `.debug` |

### Methods

| Method | Returns | Description |
|---|---|---|
| `initialize()` | `Void` | Sets up the payment session. Call once before accepting payments. |
| `charge(amount:type:order:customer:invoice:serviceFee:)` | `TransactionResult` | Executes a Tap to Pay payment. MVP supports `.sale` only. |
| `reinitializeIfNeeded()` | `Void` | Re-establishes an expired session. Called automatically by `charge()`, but can be called proactively. |

### Published Properties

| Property | Type | Description |
|---|---|---|
| `sessionState` | `SessionState` | Current SDK lifecycle state. Bindable in SwiftUI. |
| `isReady` | `Bool` | `true` when the session is active and ready to accept payments. |
| `events` | `AsyncStream<PayabliTTPEvent>` | Stream of domain events for rich UI feedback. |
| `pendingUpdates` | `[PendingUpdate]` | Failed backend updates queued for retry. |

---

## Error Handling

```swift
do {
    let result = try await ttp.charge(amount: 25.00, type: .sale)
} catch PayabliTTPError.notInitialized {
    // Call initialize() first
} catch PayabliTTPError.deviceNotSupported {
    // Device lacks NFC hardware
} catch PayabliTTPError.networkError(let detail) {
    // No connectivity
} catch PayabliTTPError.backendError(let code, let message) {
    // Payabli backend returned an error
} catch {
    // Unexpected error
}
```

### Error Types

| Case | Description |
|---|---|
| `.notInitialized` | `charge()` called before `initialize()` |
| `.deviceNotSupported` | Device lacks NFC support |
| `.attestationFailed(String)` | Device verification failed |
| `.networkError(String)` | Network connectivity failure |
| `.backendError(statusCode:message:)` | 4xx / 5xx from Payabli backend |
| `.fiservError(String)` | Card read failed or user cancelled NFC tap |
| `.sessionExpired` | Session expired and re-init failed |
| `.invalidState(String)` | Invalid state or unsupported payment type |

---

## Session Management

The SDK manages the payment session lifecycle automatically:

- `charge()` calls `reinitializeIfNeeded()` before every transaction — the session is always fresh.
- For optimized UX (instant charge response), call `reinitializeIfNeeded()` proactively when the payment screen appears:

```swift
.onAppear {
    Task { try? await ttp.reinitializeIfNeeded() }
}
```

### Pending Updates

If a transaction completes on device but the backend sync fails (network outage), the SDK queues it locally and retries automatically on the next `initialize()` call. Check unsynced transactions via:

```swift
if !ttp.pendingUpdates.isEmpty {
    // Show sync warning to user
}
```

---

## Session States

```
idle → ready (after initialize())
ready → sessionExpired → ready (after reinitializeIfNeeded())
any   → error(String)  → ready (recovered automatically)
```

---

## MVP Scope

| Operation | Availability |
|---|---|
| `charge(.sale)` — NFC tap sale | ✅ Available |
| `charge(.auth)` — NFC authorize | 🔜 Coming soon |
| `refund(.unmatched)`, `refund(.open)` | 🔜 Coming soon |
| Capture, matched refund, cancel, void | Call [Payabli Cloud API](https://docs.payabli.com) directly |

---

## Security

- Your `apiKey` is a Payabli publishable key — safe to include in the app binary.
- All payment processing credentials are fetched securely per-session using device-level cryptographic attestation and held in memory only — never written to disk.
- All communication is over HTTPS.

---

## License

Copyright © 2026 Payabli. All rights reserved.
