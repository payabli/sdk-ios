# Cross-platform bridges

Source for the three non-native-iOS integrations.

| Platform         | Files                                                        | Status (v1.0)                                                                           |
| ---------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| **Flutter**      | `Flutter/PayabliSDKPlugin.swift`, `Flutter/payabli_sdk.dart` | MethodChannel plugin ready for Tap to Pay and payment flow; example app scaffold at `Example/PayabliFlutterDemo/`. |
| **.NET MAUI**    | `MAUI/PayabliBinding.cs`                                     | .NET 10 iOS binding library skeleton for Tap to Pay and payment flow. Regenerate via `sharpie bind` against the XCFrameworks. |
| **React Native** | `ReactNative/PayabliSDKModule.swift`, `ReactNative/PayabliSDKModuleBridge.m`, `ReactNative/PayabliSDK.ts` | Native Module wrapper for Tap to Pay and stored card/ACH PayIn payment flow; Expo example app at `Example/PayabliReactNativeDemo/`. |

These files are **not** compiled as part of the Swift package build — they're consumed by their respective host toolchains (Flutter's Xcode project, a .NET MAUI binding project, an RN host app).

**So a change to the public surface reaches these three files and no gate catches it.** Neither Swift
file can typecheck here: `PayabliSDKPlugin.swift` imports `Flutter`, and `PayabliSDKModule.swift`
inherits `RCTEventEmitter`, which the host app's bridging header supplies. `swiftlint` reads them but
lint is not compilation, so a renamed or newly-throwing initialiser passes every check and ships broken.
Until a job builds them against their toolchains, a change to a bridged type is finished only when all
three are updated by hand:

- `Flutter/PayabliSDKPlugin.swift` and `ReactNative/PayabliSDKModule.swift` — Swift call sites.
- `MAUI/PayabliBinding.cs` — `[Export]` selectors, which must match the generated
  `PayabliSDKTapToPay-Swift.h` exactly. A throwing initialiser gains `error:`, so the selector changes
  even though the C# still compiles. Read the generated header rather than inferring the name.

`xcrun swiftc -parse <file>` validates syntax without resolving those imports, which catches a
malformed edit but not a wrong signature.

The current Flutter, .NET MAUI, and React Native payment-flow bridge surfaces
expose stored card/ACH payment-method creation. Native Swift apps should use
`PayabliSDKPayInPaymentFlow` directly for capture, authorize, and
capture-authorized transaction flows until those request models are promoted
into the bridge APIs.

For payment flow-specific bridge setup, access-token handling, and sample
stored card/ACH calls, see
[`Documentation/PayInPaymentFlowIntegrationGuide.md`](../Documentation/PayInPaymentFlowIntegrationGuide.md).
