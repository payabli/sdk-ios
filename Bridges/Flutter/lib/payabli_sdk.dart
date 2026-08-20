import 'dart:async';

import 'package:flutter/services.dart';

const MethodChannel _payabliMethodChannel = MethodChannel(
  'com.payabli.sdk/taptopay',
);
const EventChannel _payabliEventChannel = EventChannel(
  'com.payabli.sdk/taptopay/events',
);

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
    _payabliMethodChannel.setMethodCallHandler(_handleNativeCallback);

    await _payabliMethodChannel.invokeMethod<void>('configure', {
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
      await _payabliMethodChannel.invokeMethod<void>('initialize');
    } on PlatformException catch (e) {
      throw PayabliTTPException._fromPlatform(e);
    }
  }

  // MARK: - charge

  /// Runs a sale charge end-to-end: backend `/initiate` → NFC tap →
  /// backend `/update`. Returns the [paymentTransId] on success.
  static Future<String> charge({
    required PayabliTTPPaymentDetails paymentDetails,
    PayabliTTPPaymentType type = PayabliTTPPaymentType.sale,
    PayabliTTPCustomerData? customer,
    PayabliTTPInvoiceData? invoice,
    String? orderDescription,
  }) async {
    try {
      final result = await _payabliMethodChannel
          .invokeMapMethod<String, dynamic>('charge', {
            'type': type.index,
            'paymentDetails': paymentDetails._toMap(),
            if (customer != null) 'customer': customer._toMap(),
            if (invoice != null) 'invoice': invoice._toMap(),
            if (orderDescription != null) 'orderDescription': orderDescription,
          });
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
      await _payabliMethodChannel.invokeMethod<void>('activateDevice', {
        'activationCode': activationCode,
      });
    } on PlatformException catch (e) {
      throw PayabliTTPException._fromPlatform(e);
    }
  }

  // MARK: - getSessionState

  /// Polls the current `PayabliTTPSessionState`.
  static Future<PayabliTTPSessionState> getSessionState() async {
    final raw = await _payabliMethodChannel.invokeMethod<int>(
      'getSessionState',
    );
    return PayabliTTPSessionState.values[raw ?? 0];
  }

  // MARK: - events

  /// Returns the broadcast stream of lifecycle events. Multiple listeners
  /// each see all subsequent events.
  static Stream<PayabliTTPEvent> events() {
    _eventsStream ??= _payabliEventChannel
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
    if (call.method == 'accessToken') {
      final provider = PayabliPayInPaymentFlow._accessToken;
      if (provider == null) {
        throw PlatformException(
          code: 'NO_ACCESS_TOKEN_PROVIDER',
          message:
              'PayabliPayInPaymentFlow.configure() was not called with an accessTokenProvider',
        );
      }
      return await provider();
    }
    return null;
  }

  static PayabliTTPEvent _decodeEvent(dynamic raw) {
    final map = (raw as Map?)?.cast<String, dynamic>() ?? const {};
    final codeRaw = (map['code'] as int?) ?? 0;
    final payload =
        (map['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final known = codeRaw >= 0 && codeRaw < PayabliTTPEventCode.unknown.index;
    return PayabliTTPEvent(
      code: known
          ? PayabliTTPEventCode.values[codeRaw]
          : PayabliTTPEventCode.unknown,
      payload: payload,
    );
  }
}

/// Mirrors `PayabliEnvironment` raw values.
enum PayabliEnvironment { local, qa, sandbox, production }

/// Dart API for the Payabli card/ACH payment flow surface.
///
/// The access token must come from your backend. Do not embed a private
/// Payabli API key in Flutter code.
class PayabliPayInPaymentFlow {
  PayabliPayInPaymentFlow._();

  static Future<String> Function()? _accessToken;

  static Future<void> configure({
    required Future<String> Function() accessTokenProvider,
    required String entryPoint,
    PayabliEnvironment environment = PayabliEnvironment.sandbox,
  }) async {
    _accessToken = accessTokenProvider;
    _payabliMethodChannel.setMethodCallHandler(
      PayabliTTP._handleNativeCallback,
    );

    await _payabliMethodChannel.invokeMethod<void>(
      'configurePayInPaymentFlow',
      {'entryPoint': entryPoint, 'environment': environment.index},
    );
  }

  static Future<PayabliPayInPaymentFlowStoredPaymentMethod> addCard({
    required String cardNumber,
    required String expiration,
    required String cardholderName,
    required String cvv,
    required String billingZip,
    bool createAnonymous = false,
    bool forceCustomerCreation = true,
    bool temporary = false,
    String source = 'flutter-demo',
  }) async {
    try {
      final result = await _payabliMethodChannel
          .invokeMapMethod<String, dynamic>('addCard', {
            'cardNumber': cardNumber,
            'expiration': expiration,
            'cardholderName': cardholderName,
            'billingZip': billingZip,
            'cvv': cvv,
            'createAnonymous': createAnonymous,
            'forceCustomerCreation': forceCustomerCreation,
            'temporary': temporary,
            'source': source,
          });
      return PayabliPayInPaymentFlowStoredPaymentMethod._fromMap(
        result ?? const {},
      );
    } on PlatformException catch (e) {
      throw PayabliTTPException._fromPlatform(e);
    }
  }

  static Future<PayabliPayInPaymentFlowStoredPaymentMethod> addACH({
    required String accountNumber,
    required String accountType,
    required String holderName,
    required String routingNumber,
    String? secCode,
    String? holderType,
    bool achValidation = true,
    bool createAnonymous = false,
    bool forceCustomerCreation = true,
    bool temporary = false,
    String source = 'flutter-demo',
  }) async {
    try {
      final result = await _payabliMethodChannel
          .invokeMapMethod<String, dynamic>('addACH', {
            'accountNumber': accountNumber,
            'accountType': accountType,
            'holderName': holderName,
            'routingNumber': routingNumber,
            if (secCode != null) 'secCode': secCode,
            if (holderType != null) 'holderType': holderType,
            'achValidation': achValidation,
            'createAnonymous': createAnonymous,
            'forceCustomerCreation': forceCustomerCreation,
            'temporary': temporary,
            'source': source,
          });
      return PayabliPayInPaymentFlowStoredPaymentMethod._fromMap(
        result ?? const {},
      );
    } on PlatformException catch (e) {
      throw PayabliTTPException._fromPlatform(e);
    }
  }
}

class PayabliPayInPaymentFlowStoredPaymentMethod {
  const PayabliPayInPaymentFlowStoredPaymentMethod({
    required this.responseText,
    required this.apiResponse,
    this.storedMethodId,
    this.methodReferenceId,
    this.resultCode,
    this.resultText,
    this.customerId,
  });

  final String? storedMethodId;
  final String? methodReferenceId;
  final int? resultCode;
  final String? resultText;
  final int? customerId;
  final String responseText;
  final Map<String, dynamic> apiResponse;

  factory PayabliPayInPaymentFlowStoredPaymentMethod._fromMap(
    Map<String, dynamic> map,
  ) => PayabliPayInPaymentFlowStoredPaymentMethod(
    storedMethodId: map['storedMethodId'] as String?,
    methodReferenceId: map['methodReferenceId'] as String?,
    resultCode: map['resultCode'] as int?,
    resultText: map['resultText'] as String?,
    customerId: map['customerId'] as int?,
    responseText: (map['responseText'] as String?) ?? '',
    apiResponse:
        (map['apiResponse'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}

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
  attestationFailed,
  configFailed,

  /// A code this mirror has not been taught yet. The SDK appends cases, and a
  /// bridge that indexes blindly turns a newer SDK into a crash.
  unknown,
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
    this.customerId,
    this.company,
    this.billingAddress1,
    this.billingAddress2,
    this.billingCity,
    this.billingState,
    this.billingZip,
    this.billingCountry,
    this.billingPhone,
    this.billingEmail,
    this.shippingAddress1,
    this.shippingAddress2,
    this.shippingCity,
    this.shippingState,
    this.shippingZip,
    this.shippingCountry,
  });

  final String? firstName;
  final String? lastName;
  final String? customerNumber;
  final String? email;
  final String? phone;
  final int? customerId;
  final String? company;
  final String? billingAddress1;
  final String? billingAddress2;
  final String? billingCity;
  final String? billingState;
  final String? billingZip;
  final String? billingCountry;
  final String? billingPhone;
  final String? billingEmail;
  final String? shippingAddress1;
  final String? shippingAddress2;
  final String? shippingCity;
  final String? shippingState;
  final String? shippingZip;
  final String? shippingCountry;

  Map<String, dynamic> _toMap() => {
    if (firstName != null) 'firstName': firstName,
    if (lastName != null) 'lastName': lastName,
    if (customerNumber != null) 'customerNumber': customerNumber,
    if (email != null) 'email': email,
    if (phone != null) 'phone': phone,
    if (customerId != null) 'customerId': customerId,
    if (company != null) 'company': company,
    if (billingAddress1 != null) 'billingAddress1': billingAddress1,
    if (billingAddress2 != null) 'billingAddress2': billingAddress2,
    if (billingCity != null) 'billingCity': billingCity,
    if (billingState != null) 'billingState': billingState,
    if (billingZip != null) 'billingZip': billingZip,
    if (billingCountry != null) 'billingCountry': billingCountry,
    if (billingPhone != null) 'billingPhone': billingPhone,
    if (billingEmail != null) 'billingEmail': billingEmail,
    if (shippingAddress1 != null) 'shippingAddress1': shippingAddress1,
    if (shippingAddress2 != null) 'shippingAddress2': shippingAddress2,
    if (shippingCity != null) 'shippingCity': shippingCity,
    if (shippingState != null) 'shippingState': shippingState,
    if (shippingZip != null) 'shippingZip': shippingZip,
    if (shippingCountry != null) 'shippingCountry': shippingCountry,
  };
}

/// Payment-amount inputs for a charge. Mirrors `PayabliTTPPaymentDetails`.
class PayabliTTPPaymentDetails {
  const PayabliTTPPaymentDetails({
    required this.amount,
    this.serviceFee = 0,
    this.currency = 'USD',
    this.paymentDescription,
  });

  final double amount;
  final double serviceFee;
  final String currency;
  final String? paymentDescription;

  Map<String, dynamic> _toMap() => {
    'amount': amount,
    'serviceFee': serviceFee,
    'currency': currency,
    if (paymentDescription != null) 'paymentDescription': paymentDescription,
  };
}

/// Invoice information forwarded to the charge pipeline. Mirrors
/// `PayabliTTPInvoiceData`.
class PayabliTTPInvoiceData {
  const PayabliTTPInvoiceData({this.invoiceNumber});

  final String? invoiceNumber;

  Map<String, dynamic> _toMap() => {
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
