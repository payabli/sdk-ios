# PayabliSDK for iOS

Native iOS SDK for Payabli payment acceptance. Drop-in SwiftUI forms for tokenization, card-not-present processing, and card-present Tap to Pay on iPhone.

Part of the Payabli **Embedded Components V2** platform. See [RFC-0001](./RFC-0001-payabli-sdk-ios.md) for the full v1.0 design.

## Requirements

| Feature | Minimum iOS |
| --- | --- |
| Tokenization (Card / ACH) | iOS 15.0 |
| Apple Pay | iOS 15.0 |
| Tap to Pay on iPhone | iOS 16.7, iPhone XS or later |

Swift 5.9+, Xcode 15+.

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/payabli/payabli-sdk-ios.git", from: "1.0.0")
]
```

Add the products you need as target dependencies:

- `PayabliSDK` — umbrella (Core + PayIn)
- `PayabliSDKCore` — shared core only
- `PayabliSDKPayIn` — tokenization, getpaid, Tap to Pay

### CocoaPods

```ruby
pod 'PayabliSDK', '~> 1.0'              # umbrella (Core + PayIn)
pod 'PayabliSDK/Core', '~> 1.0'          # core only
pod 'PayabliSDK/PayIn', '~> 1.0'         # core + payin
```

## Quick start

> **Authentication model.** Your `clientSecret` must **never** ship in the mobile
> binary. Your backend performs the token exchange server-side against
> `POST /api/v2/token/serverside` and returns a short-lived `access_token` to
> the app. The SDK receives the pre-minted token plus an optional refresh
> callback that re-hits your backend when the token expires.

```swift
import PayabliSDKPayIn

// 1. Fetch an access token from YOUR backend (not from Payabli directly).
let accessToken = try await yourBackend.fetchPayabliAccessToken()

// 2. Configure the SDK. tokenProvider is called on 401 / expiry.
let config = PayabliConfig(
    accessToken: accessToken,
    tokenProvider: { try await yourBackend.fetchPayabliAccessToken() },
    customerId: 4440,
    entryPoint: "f743aed24a",
    environment: .sandbox
)

PayabliPayIn.shared.configure(config: config, theme: .default)

// 3. Tokenize.
let vc = PayabliPayIn.shared.createTokenizationViewController(
    type: .card
) { token, error in
    // handle result
}
present(vc, animated: true)
```

### Your backend's token endpoint

```text
POST /payabli/token  (your URL; e.g., https://your-api.example.com/payabli/token)
→ Your server calls POST https://api-sandbox.payabli.com/api/v2/token/serverside
   with your clientId + clientSecret (held in server-side config / secrets manager).
→ Returns {"access_token": "..."} to the mobile app.
```

## Components (v1.0)

| Component | Module | Status |
| --- | --- | --- |
| PayIn (tokenization, getpaid, Tap to Pay) | `PayabliSDKPayIn` | ✅ Ships v1.0 |
| Payout | `PayabliSDKPayout` | ❌ Future |
| Reporting | `PayabliSDKReporting` | ❌ Future |
| Onboarding | `PayabliSDKOnboarding` | ❌ Future |

## Demo app

```bash
cd Example/PayabliDemo
cp Config.xcconfig.sample Config.xcconfig  # fill in sandbox credentials
open PayabliDemo.xcodeproj
```

## License

Commercial. See [LICENSE](./LICENSE).
