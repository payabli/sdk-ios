# Cross-platform bridges

Source for the three non-native-iOS integrations described in RFC-0001 §5 Phase 9.

| Platform | Files | Status (v1.0) |
| --- | --- | --- |
| **Flutter** | `Flutter/PayabliSDKPlugin.swift`, `Flutter/payabli_sdk.dart` | MethodChannel plugin ready; example app scaffold at `Example/PayabliFlutterDemo/`. |
| **.NET MAUI** | `MAUI/PayabliBinding.cs` | C# iOS Binding Library skeleton. Regenerate via `sharpie bind` against the XCFramework. |
| **React Native** | `ReactNative/PayabliSDKModule.swift` | Native Module architecture only (FR-9.1); RN example app is future work. |

These files are **not** compiled as part of the Swift package build — they're consumed by their respective host toolchains (Flutter's Xcode project, a .NET MAUI binding project, an RN host app).
