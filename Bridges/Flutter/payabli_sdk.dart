import 'dart:async';

import 'package:flutter/services.dart';

/// Dart API for the Payabli iOS SDK — Tap to Pay on iPhone surface.
///
/// Communicates with the native iOS SDK via two channels declared in
/// `Bridges/Flutter/PayabliSDKPlugin.swift`:
///   - `com.payabli.sdk/taptopay` (`MethodChannel`): RPC for configure /
///     initialize / charge / activateDevice / getSessionState.
///   - `com.payabli.sdk/taptopay/events` (`EventChannel`): one-way stream of
///     [PayabliTTPEvent]s mirroring `PayabliTTPEvent.code` + `payload`.
///
/// ## Authentication
///
/// Your Flutter app must obtain the access token from your **own backend**
/// (which holds the Payabli `clientSecret` server-side) and pass it in via
/// [configure]. The native SDK calls back via the `refreshToken` channel
/// method when the token expires — supply a [tokenProvider] callback that
/// hits your backend and returns a fresh token.
///
/// ## Tap to Pay requirements
///
///   - Apple's `proximity-reader.payment.acceptance` entitlement on the
///     iOS host app target (request to Apple).
///   - `App Attest` entitlement (`devicecheck.appattest-environment`).
///   - A physical iPhone XS or newer running iOS 16.7+.
class PayabliTTP {
  PayabliTTP._();

  static const MethodChannel _methodChannel =
      MethodChannel('com.payabli.sdk/taptopay');
  static const EventChannel _eventChannel =
      EventChannel('com.payabli.sdk/taptopay/events');

  static Future<String> Function()? _tokenRefresh;
  static Stream<PayabliTTPEvent>? _eventsStream;

  // MARK: - configure

  /// Configures the underlying `PayabliTTP` instance. Call once per app
  /// launch, before [initialize].
  static Future<void> configure({
    required String accessToken,
    required Future<String> Function() tokenProvider,
    required String entryPoint,
    required String appId,
    PayabliEnvironment environment = PayabliEnvironment.sandbox,
  }) async {
    _tokenRefresh = tokenProvider;
    _methodChannel.setMethodCallHandler(_handleNativeCallback);

    await _methodChannel.invokeMethod<void>('configure', {
      'accessToken': accessToken,
      'entryPoint': entryPoint,
      'appId': appId,
      'environment': environment.index,
    });
  }

  // MARK: - initialize

  /// Runs the cold/warm attestation + config + reader-prepare pipeline.
  /// Resolves when the session reaches [PayabliTTPSessionState.ready], or
  /// throws a [PayabliTTPException] on any failure.
  static Future<void> initialize() async {
    try {
      await _methodChannel.invokeMethod<void>('initialize');
    } on PlatformException catch (e) {
      throw PayabliTTPException._fromPlatform(e);
    }
  }

  // MARK: - charge

  /// Runs a sale charge end-to-end: backend `/initiate` → NFC tap →
  /// backend `/update`. Returns the [paymentTransId] on success.
  static Future<String> charge({
    required double amount,
    PayabliTTPPaymentType type = PayabliTTPPaymentType.sale,
    double serviceFee = 0,
    PayabliTTPCustomerData? customer,
    PayabliTTPOrderData? order,
  }) async {
    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>(
        'charge',
        {
          'amount': amount,
          'type': type.index,
          'serviceFee': serviceFee,
          if (customer != null) 'customer': customer._toMap(),
          if (order != null) 'order': order._toMap(),
        },
      );
      final paymentTransId = result?['paymentTransId'] as String?;
      if (paymentTransId == null) {
        throw const PayabliTTPException(
          code: 'CHARGE_FAILED',
          message: 'Native charge returned no paymentTransId',
        );
      }
      return paymentTransId;
    } on PlatformException catch (e) {
      throw PayabliTTPException._fromPlatform(e);
    }
  }

  // MARK: - activateDevice

  /// Activates a pending device using an out-of-band activation code.
  static Future<void> activateDevice({required String activationCode}) async {
    try {
      await _methodChannel.invokeMethod<void>('activateDevice', {
        'activationCode': activationCode,
      });
    } on PlatformException catch (e) {
      throw PayabliTTPException._fromPlatform(e);
    }
  }

  // MARK: - getSessionState

  /// Polls the current `PayabliTTPSessionState`.
  static Future<PayabliTTPSessionState> getSessionState() async {
    final raw = await _methodChannel.invokeMethod<int>('getSessionState');
    return PayabliTTPSessionState.values[raw ?? 0];
  }

  // MARK: - events

  /// Returns the broadcast stream of lifecycle events. Multiple listeners
  /// each see all subsequent events.
  static Stream<PayabliTTPEvent> events() {
    _eventsStream ??= _eventChannel
        .receiveBroadcastStream()
        .map(_decodeEvent)
        .asBroadcastStream();
    return _eventsStream!;
  }

  // MARK: - Internals

  static Future<dynamic> _handleNativeCallback(MethodCall call) async {
    if (call.method == 'refreshToken') {
      final provider = _tokenRefresh;
      if (provider == null) {
        throw PlatformException(
          code: 'NO_TOKEN_PROVIDER',
          message: 'configure() was not called with a tokenProvider',
        );
      }
      return await provider();
    }
    return null;
  }

  static PayabliTTPEvent _decodeEvent(dynamic raw) {
    final map = (raw as Map?)?.cast<String, dynamic>() ?? const {};
    final codeRaw = (map['code'] as int?) ?? 0;
    final payload = (map['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PayabliTTPEvent(
      code: PayabliTTPEventCode.values[codeRaw],
      payload: payload,
    );
  }
}

/// Mirrors `PayabliEnvironment` raw values.
enum PayabliEnvironment { local, qa, sandbox, production }

/// Mirrors `PayabliTTPPaymentType`. v1.0 supports only [sale].
enum PayabliTTPPaymentType { sale }

/// Mirrors `PayabliTTPSessionState` (raw indices match the @objc Int enum).
enum PayabliTTPSessionState {
  idle,
  attestingDevice,
  fetchingConfig,
  initializingReader,
  ready,
  sessionExpired,
  reinitializing,
  pendingActivation,
  error,
}

/// Mirrors `PayabliTTPEventCode` (raw indices match the @objc Int enum).
enum PayabliTTPEventCode {
  attestationStarted,
  attestationCompleted,
  configReceived,
  readerInitializing,
  readerReady,
  chargeInitiated,
  nfcStarted,
  nfcCompleted,
  nfcFailed,
  updateCompleted,
  updateFailed,
  sessionExpired,
  reinitializeStarted,
  reinitializeCompleted,
  devicePendingActivation,
  activationStarted,
  activationCompleted,
  activationFailed,
}

/// One lifecycle event emitted by [PayabliTTP.events]. Use [code] for
/// pattern matching and [payload] for the case-specific data (see
/// `PayabliTTPEvent.payload` in the native module for the schema).
class PayabliTTPEvent {
  const PayabliTTPEvent({required this.code, required this.payload});

  final PayabliTTPEventCode code;
  final Map<String, dynamic> payload;

  String? get paymentTransId => payload['paymentTransId'] as String?;
  String? get error => payload['error'] as String?;

  @override
  String toString() => 'PayabliTTPEvent($code, $payload)';
}

/// Customer information forwarded to the charge pipeline. Mirrors
/// `PayabliTTPCustomerData` / `PayabliTTPCustomerDataObjC` field-for-field.
class PayabliTTPCustomerData {
  const PayabliTTPCustomerData({
    this.firstName,
    this.lastName,
    this.customerNumber,
    this.email,
    this.phone,
  });

  final String? firstName;
  final String? lastName;
  final String? customerNumber;
  final String? email;
  final String? phone;

  Map<String, String?> _toMap() => {
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (customerNumber != null) 'customerNumber': customerNumber,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
      };
}

/// Order information forwarded to the charge pipeline. Mirrors
/// `PayabliTTPOrderData` / `PayabliTTPOrderDataObjC` field-for-field.
class PayabliTTPOrderData {
  const PayabliTTPOrderData({
    this.orderId,
    this.orderDescription,
    this.invoiceNumber,
  });

  final String? orderId;
  final String? orderDescription;
  final String? invoiceNumber;

  Map<String, String?> _toMap() => {
        if (orderId != null) 'orderId': orderId,
        if (orderDescription != null) 'orderDescription': orderDescription,
        if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
      };
}

/// Thrown by [PayabliTTP] methods. [code] mirrors the native error code:
///   - `"TTP_<n>"` when the underlying error is a `PayabliTTPError`
///     (`<n>` matches the stable code documented in the native module).
///   - `"INIT_FAILED"`, `"CHARGE_FAILED"`, `"ACTIVATION_FAILED"`,
///     `"INVALID_ARGS"`, `"NOT_CONFIGURED"`, `"NO_TOKEN_PROVIDER"` for
///     bridge-level failures.
class PayabliTTPException implements Exception {
  const PayabliTTPException({required this.code, required this.message});

  final String code;
  final String message;

  factory PayabliTTPException._fromPlatform(PlatformException e) =>
      PayabliTTPException(code: e.code, message: e.message ?? '');

  @override
  String toString() => 'PayabliTTPException($code): $message';
}
