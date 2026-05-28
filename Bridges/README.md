# Cross-platform bridges

Source for the three non-native-iOS integrations.

| Platform         | Files                                                        | Status (v1.0)                                                                           |
| ---------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| **Flutter**      | `Flutter/PayabliSDKPlugin.swift`, `Flutter/payabli_sdk.dart` | MethodChannel plugin ready for Tap to Pay and payment method; example app scaffold at `Example/PayabliFlutterDemo/`. |
| **.NET MAUI**    | `MAUI/PayabliBinding.cs`                                     | .NET 10 iOS binding library skeleton for Tap to Pay and payment method. Regenerate via `sharpie bind` against the XCFrameworks. |
| **React Native** | `ReactNative/PayabliSDKModule.swift`                         | Native Module architecture only (FR-9.1); RN example app is future work.                |

These files are **not** compiled as part of the Swift package build — they're consumed by their respective host toolchains (Flutter's Xcode project, a .NET MAUI binding project, an RN host app).

For payment method-specific bridge setup, access-token handling, and sample
card/ACH calls, see
[`Documentation/PaymentMethodIntegrationGuide.md`](../Documentation/PaymentMethodIntegrationGuide.md).
