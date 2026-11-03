# Other technologies

How to take Payabli payments on iPhone from an app built with React Native or Flutter. This guide is part of the
[Payabli iOS SDK](../README.md); set up the SDK and its session there first.

> [!IMPORTANT]
> **Notice:** This SDK is in beta. Its public interface can change in ways that aren't backward compatible. See
> [Versioning and support](../README.md#versioning-and-support).

> [!NOTE]
> **Guidance only:** This guide suggests one way to take Payabli payments from a React Native or Flutter app.
> It's guidance, not a supported implementation. Payabli doesn't state that any example here is a complete or
> direct implementation, or that it fits your app as written. The examples are subject to limitations, including
> the frameworks' own versions and requirements, and Payabli doesn't build or test them. Your team designs,
> builds, tests and maintains its integration, and is responsible for it.

## How it works

There is no React Native or Flutter package. Your app adds a small native module that exposes a few calls to
JavaScript or Dart, and runs this SDK underneath on iOS and the Payabli Android SDK on Android. The same applies to
any other technology, such as .NET MAUI: it binds the Objective-C surface in
[Language support](../README.md#language-support).

```
React Native or Flutter UI
        │  initialize · payWithCard · tapToPay · presentTerms · activateDevice · sessionState
        ▼
your native module (Expo module or Turbo Native Module · Pigeon or platform channels)
        │
        ▼
Payabli iOS SDK  ──▶  Payabli
        ▲
        └── token provider (Swift) ──▶ your backend's token endpoint
```

A module keeps these rules:

- **Card data never crosses into JavaScript or Dart.** The module presents the SDK's own form and the Tap to Pay
  sheet, and returns only the outcome.
- **The token is fetched natively.** The module's token provider calls your token endpoint from Swift. Your client
  ID and client secret stay on your backend.
- **Every call resolves or rejects exactly once**, including when the customer closes the form.

| | iPhone |
|---|---|
| Card-not-present: card or bank account in the SDK's form | Yes |
| Tap to Pay | Yes, on a physical iPhone set up as the [Tap to Pay guide](../Sources/PayabliSDKTapToPay/README.md) describes |

## The module's calls

Give the module the same calls on both platforms, so your JavaScript or Dart has one code path:

| Call | What it does | Result |
|---|---|---|
| `initialize(entryPoint, environment)` | Starts the app's one Payabli session. Call it once, at startup or before the first payment | Nothing, or an error with a `code` |
| `payWithCard({ amount, orderId })` | Presents the SDK's card-not-present form | A `PaymentOutcome` |
| `tapToPay({ amount, orderId })` | Takes a Tap to Pay payment on iPhone. On Android it answers `unsupported` | A `PaymentOutcome` |
| `presentTerms()` | Shows Apple's Tap to Pay terms to the merchant. On Android it answers `false` | Whether they accepted |
| `activateDevice(code)` | Activates this iPhone for Tap to Pay with its 6-digit code. On Android it rejects with `UNSUPPORTED` | Nothing, or an error with a `code` |
| `sessionState` (a stream) | Tap to Pay readiness, one value per change. On Android it sends `idle` once | `idle`, `attestingDevice`, `fetchingConfig`, `initializingReader`, `ready`, `sessionExpired`, `reinitializing`, `pendingActivation`, `pendingTerms`, `charging` or `failed` |

A `PaymentOutcome` is one of three answers, the same for both ways to pay:

| `status` | Meaning | What your app does |
|---|---|---|
| `charged` | The payment was taken | Store `paymentTransId` with the order. Don't charge again |
| `notCharged` | It wasn't taken, for example a decline | Let the customer try again |
| `unknown` | It may have been taken | Look the payment up by `paymentTransId` before charging again. Without one, find it by your `orderId` on card-not-present, or in the Payabli portal for Tap to Pay |

`tapToPay` answers a fourth status, `unsupported`, where Tap to Pay isn't available. A failure that isn't a payment
outcome, such as a session that didn't start, rejects the call in React Native and throws a `PlatformException` in
Flutter, with a `code`. [Handle the outcome](../README.md#handle-the-outcome) lists the SDK results each status
comes from.

## React Native

Use the [Expo Modules API](https://docs.expo.dev/modules/overview/). You write the module's TypeScript half and its
Swift half, including Swift `async` functions. It works in an Expo app and, after
`npx install-expo-modules@latest`, in a bare React Native app. React Native's own Turbo Native Modules work too; see
[Using a Turbo Native Module instead](#using-a-turbo-native-module-instead).

Expo Go can't load your own native code, so run a development build (`npx expo run:ios`).

### 1. Create the module

From the folder that holds your app's `package.json`:

```sh
npx create-expo-module@latest --local
```

Name it `payabli`. The command creates `modules/payabli/` with `ios/`, `android/`, `src/` and `index.ts`. Add this
SDK to the module's iOS project as [Installation](../README.md#installation) describes.

### 2. Type the module in TypeScript

```ts
// modules/payabli/src/Payabli.types.ts
export type Environment = 'sandbox' | 'production';

export type PaymentRequest = {
  amount: number;   // in dollars, for example 12.34
  orderId: string;  // your own reference, to find a card-not-present payment whose outcome is unknown
};

export type PaymentOutcome =
  | { status: 'charged' | 'notCharged' | 'unknown'; paymentTransId: string | null }
  | { status: 'unsupported' };

export type SessionState =
  | 'idle' | 'attestingDevice' | 'fetchingConfig' | 'initializingReader' | 'ready'
  | 'sessionExpired' | 'reinitializing' | 'pendingActivation' | 'pendingTerms' | 'charging' | 'failed';

export type PayabliEvents = {
  onSessionState(event: { state: SessionState }): void;
};
```

```ts
// modules/payabli/src/PayabliModule.ts
import { NativeModule, requireNativeModule } from 'expo';
import type { Environment, PaymentOutcome, PaymentRequest, PayabliEvents } from './Payabli.types';

declare class PayabliModule extends NativeModule<PayabliEvents> {
  initialize(entryPoint: string, environment: Environment): Promise<void>;
  payWithCard(request: PaymentRequest): Promise<PaymentOutcome>;
  tapToPay(request: PaymentRequest): Promise<PaymentOutcome>;
  presentTerms(): Promise<boolean>;
  activateDevice(code: string): Promise<void>;
}

export default requireNativeModule<PayabliModule>('Payabli');
```

```ts
// modules/payabli/index.ts
export { default as Payabli } from './src/PayabliModule';
export * from './src/Payabli.types';
```

### 3. Start the session once

```tsx
// App.tsx
import { useEffect, useState } from 'react';
import { Payabli } from './modules/payabli';

export default function App() {
  const [started, setStarted] = useState(false);
  const [startError, setStartError] = useState<string | null>(null);

  useEffect(() => {
    Payabli.initialize('your-entry-point', 'sandbox')
      .then(() => setStarted(true))
      .catch((e: { code?: string }) => setStartError(e.code ?? 'ERROR'));
  }, []);

  if (startError) return <SetupError code={startError} />;
  return started ? <Checkout orderId="A-1001" amount={12.34} /> : <Starting />;
}
```

Calling `initialize` again with the same entry point and environment returns the session already running.

### 4. Take a payment and handle the outcome

```tsx
// Checkout.tsx
import { useRef, useState } from 'react';
import { Button, Platform, Text, View } from 'react-native';
import { Payabli, type PaymentOutcome } from './modules/payabli';

export function Checkout({ orderId, amount }: { orderId: string; amount: number }) {
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const paying = useRef(false); // set synchronously, so a second tap before the re-render can't start a payment

  async function pay(way: 'card' | 'tap') {
    if (paying.current) return;
    paying.current = true;
    setBusy(true);
    let canPayAgain = true;
    try {
      const request = { amount, orderId };
      const outcome = way === 'card' ? await Payabli.payWithCard(request) : await Payabli.tapToPay(request);
      canPayAgain = outcome.status === 'notCharged' || outcome.status === 'unsupported';
      setMessage(describe(outcome));
    } catch (e) {
      const error = e as { code?: string; message: string };
      setMessage(`Couldn't take the payment (${error.code ?? 'ERROR'})`);
    } finally {
      // A charged order isn't paid again, and an unknown one stays blocked until checkWithBackend settles it.
      if (canPayAgain) {
        paying.current = false;
        setBusy(false);
      }
    }
  }

  return (
    <View>
      <Button title="Pay by card" disabled={busy} onPress={() => pay('card')} />
      {Platform.OS === 'ios' && <Button title="Tap to Pay" disabled={busy} onPress={() => pay('tap')} />}
      <Text>{message}</Text>
    </View>
  );
}

function describe(outcome: PaymentOutcome): string {
  switch (outcome.status) {
    case 'charged':
      saveTransaction(outcome.paymentTransId); // store it with the order; don't log it
      return 'Paid';
    case 'notCharged':
      return 'Not charged. Try again.';
    case 'unknown':
      checkWithBackend(outcome.paymentTransId); // look it up before charging again
      return 'Checking the payment…';
    case 'unsupported':
      return "Tap to Pay isn't available on this phone.";
  }
}
```

A native error arrives as a JavaScript `Error` with `code` and `message`. Branch on `code`, and log only the code: an
SDK error's message can quote what the customer entered.

### 5. Show Tap to Pay readiness

```tsx
import { useEvent } from 'expo';
import { Button, Text } from 'react-native';
import { Payabli } from './modules/payabli';

export function TapToPayStatus() {
  const { state } = useEvent(Payabli, 'onSessionState', { state: 'idle' }) ?? { state: 'idle' };

  switch (state) {
    case 'ready': return <Text>Ready</Text>;
    case 'attestingDevice':
    case 'fetchingConfig':
    case 'initializingReader':
    case 'reinitializing': return <Text>Preparing the phone…</Text>;
    case 'charging': return <Text>Hold the card near the top of the iPhone</Text>;
    case 'pendingTerms': return <Button title="Review Apple's terms" onPress={() => Payabli.presentTerms()} />;
    case 'pendingActivation': return <ActivationCodeForm onSubmit={code => Payabli.activateDevice(code)} />;
    case 'failed': return <Text>Tap to Pay stopped. Contact support if it keeps happening.</Text>;
    default: return null;
  }
}
```

Outside a component, subscribe with `Payabli.addListener('onSessionState', listener)` and call `remove()` on the
result when you're done. Keep the activation code as a string: it's six digits and can start with zero.

### 6. The Swift half

Each call is one SDK call underneath:

| Call | iOS SDK |
|---|---|
| `initialize` | `PayabliSession.initialize(config:)` |
| `payWithCard` | present `PayabliPayInView` for a `PayabliPayIn` with `operation: .capture` |
| `tapToPay` | `PayabliTTP.create()`, `initialize()`, then `charge(paymentDetails:)` |
| `presentTerms` | `presentTerms()`, `areTermsAccepted()`, then `initialize()` when they accepted |
| `activateDevice` | `activateDevice(activationCode:)`, then `initialize()` |
| `sessionState` | `PayabliTTP`'s `$sessionState` |

Run the payment calls on the main queue so the SDK's screens can be presented, and resolve the promise exactly once:

```swift
import ExpoModulesCore
import PayabliSDKCore
import PayabliSDKPayIn
import SwiftUI

AsyncFunction("payWithCard") { (request: PaymentRequestRecord, promise: Promise) in
  guard let session = self.session,
        let presenter = self.appContext?.utilities?.currentViewController() else {
    return promise.reject("NO_SESSION", "Call initialize first")
  }
  let payIn = PayabliPayIn(
    session: session,
    operation: .capture,
    requestConfiguration: PayabliPayInRequestConfiguration(
      paymentDetails: PayabliPayInPaymentDetails(totalAmount: request.amount),
      orderId: request.orderId
    )
  )
  weak var sheet: UIViewController?
  var settled = false
  let finish = { (outcome: [String: Any?]) in
    guard !settled else { return }
    settled = true
    sheet?.dismiss(animated: true)
    promise.resolve(outcome)
  }
  let host = UIHostingController(rootView: PayabliPayInView(
    component: payIn,
    onCompleted: { result in
      finish(["status": "charged", "paymentTransId": result.transaction?.paymentTransId])
    },
    onError: { error in finish(cardOutcome(for: error)) }
  ))
  sheet = host
  presenter.present(host, animated: true)
}.runOnQueue(.main)
```

`PaymentRequestRecord` is an Expo `Record` with `amount` and `orderId` fields, matching the TypeScript
`PaymentRequest`. When the customer closes the sheet before the SDK reports, call `finish` with `unknown` from its
dismissal: a submission may already be in flight, so your app checks the payment before charging again. `settled`
makes the dismissal and the SDK's callbacks resolve the promise once between them.

Map the SDK's errors to the outcome as [Handle the outcome](../README.md#handle-the-outcome) does:

```swift
func cardOutcome(for error: Error) -> [String: Any?] {
  switch error {
  case let PayabliPayInError.submissionInterrupted(_, _, paymentTransId, _):
    return ["status": "unknown", "paymentTransId": paymentTransId]
  case is CancellationError:
    return ["status": "unknown", "paymentTransId": nil]
  default:
    return ["status": "notCharged", "paymentTransId": nil]
  }
}

func tapOutcome(for error: Error) -> [String: Any?] {
  guard let error = error as? TapToPayError else {
    // charge throws a CancellationError only before the card is read.
    return ["status": "notCharged", "paymentTransId": nil]
  }
  switch error.capture {
  case .notCharged: return ["status": "notCharged", "paymentTransId": error.paymentTransId]
  case .unknown: return ["status": "unknown", "paymentTransId": error.paymentTransId]
  case .charged: return ["status": "charged", "paymentTransId": error.paymentTransId]
  }
}
```

A `TapToPayError` whose `capture` is `.charged` was taken but not confirmed. Report `charged`, and reconcile it as the
[Tap to Pay guide](../Sources/PayabliSDKTapToPay/README.md#outcomes-and-errors) describes.

For `sessionState`, subscribe to `$sessionState` once the module creates its `PayabliTTP`, and send the case name of
each value with `sendEvent("onSessionState", ["state": ...])`. The cases with values, `initializingReader`,
`pendingActivation`, `failed` and `charging`, send their name only.

### Using a Turbo Native Module instead

If you'd rather not depend on `expo`, declare the same calls as a Turbo Native Module spec. Codegen generates the
native interfaces from it.

```ts
// specs/NativePayabli.ts
import type { TurboModule, CodegenTypes } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export type PaymentRequest = { amount: number; orderId: string };
export type PaymentOutcome = { status: string; paymentTransId: string | null };
export type SessionStateEvent = { state: string };

export interface Spec extends TurboModule {
  initialize(entryPoint: string, environment: string): Promise<void>;
  payWithCard(request: PaymentRequest): Promise<PaymentOutcome>;
  tapToPay(request: PaymentRequest): Promise<PaymentOutcome>;
  presentTerms(): Promise<boolean>;
  activateDevice(code: string): Promise<void>;
  readonly onSessionState: CodegenTypes.EventEmitter<SessionStateEvent>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('NativePayabli');
```

- Name the spec file with the `Native` prefix, and add a `codegenConfig` block to `package.json`.
- Keep `status` and `state` as `string` in the spec, and narrow them to the TypeScript unions above in a small
  wrapper.
- Subscribe with `const sub = NativePayabli.onSessionState(listener)` and call `sub.remove()` when you're done.
- A Turbo Native Module's class is Objective-C++. Have it call a Swift file that makes the SDK calls above. The
  card-not-present form is a SwiftUI view, which Objective-C can't present.

## Flutter

Use [Pigeon](https://pub.dev/packages/pigeon) to generate the platform channel code. You describe the calls once in
Dart, and Pigeon generates a typed Dart API and a Swift protocol your module implements. Plain platform channels
work too; see [Using platform channels instead](#using-platform-channels-instead).

### 1. Describe the calls

Add `pigeon` to `dev_dependencies`, and put the definition outside `lib/`:

```dart
// pigeons/payabli_api.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/payabli_api.g.dart',
  dartOptions: DartOptions(),
  swiftOut: 'ios/Runner/PayabliApi.g.swift',
  swiftOptions: SwiftOptions(),
  kotlinOut: 'android/app/src/main/kotlin/com/yourcompany/app/PayabliApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.yourcompany.app'),
))
enum Environment { sandbox, production }

enum PaymentStatus { charged, notCharged, unknown, unsupported }

enum SessionState {
  idle, attestingDevice, fetchingConfig, initializingReader, ready,
  sessionExpired, reinitializing, pendingActivation, pendingTerms, charging, failed,
}

class PaymentRequest {
  PaymentRequest({required this.amount, required this.orderId});
  double amount;
  String orderId;
}

class PaymentResult {
  PaymentResult({required this.status});
  PaymentStatus status;
  String? paymentTransId;
}

@HostApi()
abstract class PayabliHostApi {
  @async
  void initialize(String entryPoint, Environment environment);
  @async
  PaymentResult payWithCard(PaymentRequest request);
  @async
  PaymentResult tapToPay(PaymentRequest request);
  @async
  bool presentTerms();
  @async
  void activateDevice(String code);
}

@EventChannelApi()
abstract class PayabliEventApi {
  SessionState sessionState();
}
```

Generate the code:

```sh
dart run pigeon --input pigeons/payabli_api.dart
```

Generate every file with the same Pigeon version, and run the command again after each change to the definition.

### 2. Wrap it in a service

Keep the generated types inside one class, and give the rest of the app your own outcome type:

```dart
// lib/payabli_service.dart
import 'src/payabli_api.g.dart';

sealed class PaymentOutcome {
  const PaymentOutcome();
}
final class Charged extends PaymentOutcome {
  const Charged(this.paymentTransId);
  final String? paymentTransId;
}
final class NotCharged extends PaymentOutcome {
  const NotCharged();
}
final class OutcomeUnknown extends PaymentOutcome {
  const OutcomeUnknown(this.paymentTransId);
  final String? paymentTransId;
}
final class Unsupported extends PaymentOutcome {
  const Unsupported();
}

class PayabliService {
  PayabliService({PayabliHostApi? api}) : _api = api ?? PayabliHostApi();
  final PayabliHostApi _api;

  Future<void> initialize(String entryPoint, {bool sandbox = true}) =>
      _api.initialize(entryPoint, sandbox ? Environment.sandbox : Environment.production);

  Future<PaymentOutcome> payWithCard(double amount, String orderId) async =>
      _outcome(await _api.payWithCard(PaymentRequest(amount: amount, orderId: orderId)));

  Future<PaymentOutcome> tapToPay(double amount, String orderId) async =>
      _outcome(await _api.tapToPay(PaymentRequest(amount: amount, orderId: orderId)));

  Future<bool> presentTerms() => _api.presentTerms();

  Future<void> activateDevice(String code) => _api.activateDevice(code);

  Stream<SessionState> get sessionStates => sessionState();

  PaymentOutcome _outcome(PaymentResult result) => switch (result.status) {
        PaymentStatus.charged => Charged(result.paymentTransId),
        PaymentStatus.notCharged => const NotCharged(),
        PaymentStatus.unknown => OutcomeUnknown(result.paymentTransId),
        PaymentStatus.unsupported => const Unsupported(),
      };
}
```

A failure that isn't a payment outcome reaches Dart as a `PlatformException` with `code`, `message` and `details`.

### 3. Take a payment and handle the outcome

```dart
Future<void> _pay({required bool tap}) async {
  if (_busy) return; // checked before the rebuild, so a second tap can't start a payment
  setState(() => _busy = true);
  var canPayAgain = true;
  try {
    final outcome = tap
        ? await widget.payabli.tapToPay(12.34, 'A-1001')
        : await widget.payabli.payWithCard(12.34, 'A-1001');
    canPayAgain = outcome is NotCharged || outcome is Unsupported;
    final message = switch (outcome) {
      Charged(:final paymentTransId) => _saved(paymentTransId), // store it; don't log it
      NotCharged() => 'Not charged. Try again.',
      OutcomeUnknown(:final paymentTransId) => _check(paymentTransId), // look it up first
      Unsupported() => "Tap to Pay isn't available on this phone.",
    };
    if (mounted) setState(() => _message = message);
  } on PlatformException catch (e) {
    if (mounted) setState(() => _message = "Couldn't take the payment (${e.code})");
  } finally {
    // A charged order isn't paid again, and an unknown one stays blocked until _check settles it.
    if (canPayAgain && mounted) setState(() => _busy = false);
  }
}
```

`_saved` and `_check` run before the `mounted` check, so the outcome is recorded even when the screen has gone. In
your app, put them in a service that outlives the widget.

Because `PaymentOutcome` is `sealed`, the `switch` must cover every case, and the analyzer flags a missing one. Show
the Tap to Pay button only where it works, for example `if (Platform.isIOS)`.

### 4. Show Tap to Pay readiness

```dart
StreamBuilder<SessionState>(
  stream: widget.payabli.sessionStates,
  builder: (context, snapshot) => switch (snapshot.data) {
    SessionState.ready => const Text('Ready'),
    SessionState.attestingDevice ||
    SessionState.fetchingConfig ||
    SessionState.initializingReader ||
    SessionState.reinitializing => const Text('Preparing the phone…'),
    SessionState.charging => const Text('Hold the card near the top of the iPhone'),
    SessionState.pendingTerms => TextButton(
        onPressed: widget.payabli.presentTerms, child: const Text("Review Apple's terms")),
    SessionState.pendingActivation => ActivationCodeForm(onSubmit: widget.payabli.activateDevice),
    SessionState.failed => const Text('Tap to Pay stopped. Contact support if it keeps happening.'),
    _ => const SizedBox.shrink(),
  },
)
```

The stream starts listening on the native side when its first listener subscribes, and stops when the last one
cancels.

### 5. The Swift half

Implement the generated `PayabliHostApi` in Swift with the calls in [The Swift half](#6-the-swift-half) of the React
Native section, and map errors with the same `cardOutcome` and `tapOutcome`. Complete the call with
`.failure(PigeonError(...))` for a failure that isn't a payment outcome; Dart receives it as a `PlatformException`.

Register it in `AppDelegate`'s `didInitializeImplicitFlutterEngine`. Flutter 3.41 and later use the `UIScene`
lifecycle by default, so registering in `application(_:didFinishLaunchingWithOptions:)` doesn't work:

```swift
func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
  GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  let messenger = engineBridge.applicationRegistrar.messenger()
  PayabliHostApiSetup.setUp(binaryMessenger: messenger, api: PayabliBridge())
  SessionStateStreamHandler.register(with: messenger, streamHandler: PayabliStateStream())
}
```

### Using platform channels instead

Without Pigeon, the same calls run over a `MethodChannel`, and the session state over an `EventChannel`. The names
must match exactly on the Dart and Swift sides:

```dart
const _calls = MethodChannel('com.yourcompany.app/payabli');
const _state = EventChannel('com.yourcompany.app/payabli/state');

Future<Map<String, Object?>> payWithCard(double amount, String orderId) async {
  final result = await _calls.invokeMapMethod<String, Object?>(
      'payWithCard', {'amount': amount, 'orderId': orderId});
  return result ?? const {'status': 'unknown'};
}

Stream<String> get sessionState => _state.receiveBroadcastStream().map((e) => e as String);
```

`invokeMethod` throws `PlatformException` when the native side reports an error, and `MissingPluginException` when
nothing on the native side handles the method.

## Common problems

| Situation | What happens |
|---|---|
| Tap to Pay in the iOS Simulator | Not supported. Use a physical iPhone |
| React Native in Expo Go | Your native module isn't loaded. Use a development build |
| Flutter: `MissingPluginException` | The handler isn't registered, or it's registered in `application(_:didFinishLaunchingWithOptions:)` instead of `didInitializeImplicitFlutterEngine` |
| Flutter: generated code doesn't match | The Dart and Swift files came from different Pigeon versions. Generate them again |
| A payment call never returns | The module didn't resolve. Every call must resolve or reject exactly once, including when the customer closes the form |
| The token provider routes through JavaScript or Dart | Give each request its own pending promise or future, and fail it after 30 seconds. One shared slot can leave a request waiting forever |

## Go live

- A token endpoint on your backend that authenticates the caller, as
  [Build your token endpoint](../README.md#build-your-token-endpoint) describes.
- A production entry point and production credentials, and `production` passed to `initialize`. Start on sandbox.
- For Tap to Pay on iPhone, the setup in the [Tap to Pay guide](../Sources/PayabliSDKTapToPay/README.md#go-live).
- Never log a card number, token, CVV, expiry date, cardholder name or account number, in JavaScript, Dart or Swift.

## Related docs

| Topic | Link |
|---|---|
| This SDK | [README](../README.md) · [Card-not-present](../Sources/PayabliSDKPayIn/README.md) · [Tap to Pay](../Sources/PayabliSDKTapToPay/README.md) |
| Expo Modules API | [Overview](https://docs.expo.dev/modules/overview/) · [Module API](https://docs.expo.dev/modules/module-api/) · [Bare React Native apps](https://docs.expo.dev/bare/installing-expo-modules/) |
| Turbo Native Modules | [Introduction](https://reactnative.dev/docs/turbo-native-modules-introduction) · [Events](https://reactnative.dev/docs/the-new-architecture/native-modules-custom-events) · [Swift](https://reactnative.dev/docs/the-new-architecture/turbo-modules-with-swift) |
| Flutter | [Platform channels](https://docs.flutter.dev/platform-integration/platform-channels) · [Pigeon](https://pub.dev/packages/pigeon) · [UIScene migration](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate) |
