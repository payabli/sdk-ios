# Cross-platform bridges

Examples of integrating the SDK from Flutter, .NET MAUI and React Native. Use them as a starting point for your
own integration. They're examples rather than separate products.

| Technology       | Files                                                        | What it shows                                                                           |
| ---------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| **Flutter**      | `Flutter/PayabliSDKPlugin.swift`, `Flutter/payabli_sdk.dart` | A MethodChannel plugin for Tap to Pay and the payment flow, with an example app at `Example/PayabliFlutterDemo/`. |
| **.NET MAUI**    | `MAUI/PayabliBinding.cs`                                     | A .NET 10 iOS binding library for Tap to Pay and the payment flow. Regenerate it with `sharpie bind` against the XCFrameworks. |
| **React Native** | `ReactNative/PayabliSDKModule.swift`, `ReactNative/PayabliSDKModuleBridge.m`, `ReactNative/PayabliSDK.ts` | A Native Module for Tap to Pay and the stored card and bank account payment flow, with an Expo example app at `Example/PayabliReactNativeDemo/`. |

These files aren't compiled as part of the Swift package build. Each is built by its own toolchain: the
Flutter Xcode project, a .NET MAUI binding project, or a React Native host app.

The Flutter, .NET MAUI and React Native examples create stored card and bank account payment methods. For
capture, authorize and capture-authorized flows, use `PayabliSDKPayIn` from Swift.

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
