# PayabliDemo

SwiftUI demo app exercising every public `PayabliPayIn` API. Maps to the manual QA checklist in PRD §12.3.

## Setup

1. Open Xcode and create a new **iOS App** project named `PayabliDemo` at this directory.
2. Choose **SwiftUI** for the interface and **Swift** for the language.
3. Add the local Swift package dependency:
   - In Xcode: **File → Add Packages → Add Local…** and select the repository root.
   - Pick the `PayabliSDK` product.
4. Drag `PayabliDemoApp.swift` and `HomeView.swift` into the Xcode project.
5. Copy `Secrets.swift.sample` to `Secrets.swift` and fill in your sandbox credentials. `Secrets.swift` is gitignored.

## What it covers

- **Tokenization** — SwiftUI: `CardFormView(customerId:...)` / `ACHFormView(customerId:...)` or their `.payabliCardSheet` / `.payabliAchSheet` view modifiers. UIKit: `createTokenizationViewController(...)` or `tokenize(...)` (async) (FR-1, FR-2, FR-6.2).
- **Payment (getpaid)** — SwiftUI: `CardFormView(paymentRequest:...)` / `ACHFormView(paymentRequest:...)` or their `.payabliCardSheet` / `.payabliAchSheet` modifiers. UIKit: `processPaymentViewController(...)` or `processPayment(...)` (async) (FR-12A).
- **Stored-method headless** — via `chargeStoredMethod(...)` (FR-12B, §9.3C).
- **Theming** — custom `primaryColorHex` + `cornerRadius` applied across forms.
- **Customization** — `strings:` (`CardFormStrings` / `ACHFormStrings`) for label/error/placeholder copy, and `allowedBrands:` (`PayabliCardBrand`) on card forms to restrict accepted networks.

## Not included in this scaffold

Xcode project files (`.xcodeproj`) — generate locally per the steps above.

Apple Pay and Tap to Pay flows require entitlements (BR-2) and physical hardware; see RFC-0001 §6.
