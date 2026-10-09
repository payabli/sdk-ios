# Cross-platform bridges

Examples of integrating the SDK from Flutter, .NET MAUI and React Native. Use them as a starting point for your
own integration. They're examples rather than separate products.

| Technology       | Files                                                        | What it shows                                                                           |
| ---------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| **Flutter**      | `Flutter/PayabliSDKPlugin.swift`, `Flutter/payabli_sdk.dart` | A MethodChannel plugin for Tap to Pay and the payment flow, with an example app at `Example/PayabliFlutterDemo/`. |
| **.NET MAUI**    | `MAUI/PayabliBinding.cs`                                     | A .NET 10 iOS binding library for Tap to Pay and the payment flow. Regenerate it with `sharpie bind` against the XCFrameworks. |
| **React Native** | `ReactNative/PayabliSDKModule.swift`, `ReactNative/PayabliSDKModuleBridge.m`, `ReactNative/PayabliSDK.ts` | A Native Module for Tap to Pay and the stored card and bank account payment flow, with an Expo example app at `Example/PayabliReactNativeDemo/`. |

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
expose stored card/bank account payment-method creation. Native Swift apps should use
`PayabliSDKPayIn` directly for capture, authorize, and
capture-authorized transaction flows until those request models are promoted
into the bridge APIs.

Each bridge runs one session with one token callback: `configure` and `configurePayIn` both take a
`tokenProvider`, and when a host calls both, the callback from the later successful call answers every token request.

The example Flutter plugin talks to the native SDK over two channels. `com.payabli.sdk` carries every call,
Tap to Pay, payment flow and session alike. `com.payabli.sdk/events` carries the Tap to Pay session state,
the same snapshot `getSessionState` returns, after every change; Dart reads it as
`PayabliTTP.sessionStates()`.

The device's identity is on the session, not on either capability: `PayabliSession.deviceId()` in Flutter and
React Native, and `PayabliSessionObjC.DeviceId` in .NET MAUI. It is `null` before a configure has succeeded and
while the device's secure storage can't be read. A Tap to Pay activation reads `activationId` from the session
state instead.

For payment flow-specific bridge setup, access-token handling, and sample
stored card/bank account calls, see
[`Documentation/PayInIntegrationGuide.md`](../Documentation/PayInIntegrationGuide.md).
