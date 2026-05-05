# PayabliFlutterDemo

Minimal Flutter demo exercising the `payabli_sdk` Dart plugin + its native
iOS bridge (`Bridges/Flutter/PayabliSDKPlugin.swift`).

## Setup

```bash
cd Example/PayabliFlutterDemo
flutter pub get

# iOS: install the native plugin and run
cd ios && pod install && cd -
flutter run
```

Before running, wire `fetchAccessTokenFromPartnerBackend()` in `lib/main.dart`
to your partner backend. Never ship the `clientSecret` in the Flutter binary.

## Not included in the scaffold

The full Flutter project structure (`ios/Runner.xcodeproj`, `android/`) —
generate with `flutter create .` inside this directory. The scaffolded files
(`pubspec.yaml`, `lib/main.dart`) are the only pieces specific to PayabliSDK.
