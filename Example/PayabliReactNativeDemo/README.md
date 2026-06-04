# PayabliReactNativeDemo

Expo React Native QA app for the Payabli iOS React Native bridge.

This app was scaffolded with:

```bash
npx create-expo-app@latest Example/PayabliReactNativeDemo --template blank-typescript
```

## What It Covers

- Tap to Pay configure, initialize, charge, activate-device, state polling, and event logging.
- PayIn stored card and ACH calls through `PayabliPayInPaymentFlow.addCard(...)` and `PayabliPayInPaymentFlow.addACH(...)`.

## Setup

```bash
cd Example/PayabliReactNativeDemo
npm install
npm run typecheck
```

The Payabli bridge is a custom native iOS module, so Expo Go cannot run it. Use an Expo development build:

```bash
npx expo prebuild --platform ios
npx expo run:ios
```

After prebuild, add the native iOS bridge to the generated app target:

- Add `Bridges/ReactNative/PayabliSDKModule.swift` to the iOS target.
- Add `Bridges/ReactNative/PayabliSDKModuleBridge.m` to the same iOS target so React Native exports the Swift module.
- Add the local Swift package products `PayabliSDKTapToPay` and `PayabliSDKPayInPaymentFlow` to the generated Xcode project. `PayabliSDKCore` and `PayabliCardReaderCore` are linked transitively where needed.
- Add Tap to Pay entitlements to the iOS target before running on a physical device.

## Secrets

Update the `Secrets` object in `App.tsx` to call your backend for short-lived Payabli access tokens. Do not embed Payabli `clientSecret` values in the app.

The PayIn calls in this React Native bridge are direct card/ACH APIs. They are useful for bridge QA, but the JavaScript host app supplies card data. Use the native hosted SwiftUI PayIn form when the integration goal is to avoid host-app access to clear PAN.
