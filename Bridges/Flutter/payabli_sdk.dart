import 'package:flutter/services.dart';

/// Dart API for the Payabli SDK (PRD FR-7).
///
/// Communicates with the native iOS SDK via the
/// `com.payabli.sdk/tokenization` MethodChannel.
///
/// ## Authentication
///
/// Your Flutter app must obtain the access token from your **own backend**
/// (which holds the Payabli `clientSecret` server-side) and pass it in via
/// [configure]. The native SDK will call back via the `refreshToken` channel
/// method when the token expires — supply a [tokenProvider] callback that
/// hits your backend and returns a fresh token.
class PayabliSDK {
  static const MethodChannel _channel = MethodChannel('com.payabli.sdk/tokenization');

  /// Matches `PayabliEnvironment` raw values.
  static const int envLocal = 0;
  static const int envQA = 1;
  static const int envSandbox = 2;
  static const int envProduction = 3;

  /// Matches `PayabliPaymentType` raw values.
  static const int typeCard = 0;
  static const int typeACH = 1;
  static const int typeApplePay = 2;
  static const int typeTapToPay = 3;

  static Future<String> Function()? _tokenRefresh;

  /// Configure the SDK. Invoke once per app launch with a pre-minted access
  /// token from your backend.
  static Future<void> configure({
    required String accessToken,
    required Future<String> Function() tokenProvider,
    required int customerId,
    required String entryPoint,
    int environment = envSandbox,
  }) async {
    _tokenRefresh = tokenProvider;
    _channel.setMethodCallHandler(_handleCallback);

    await _channel.invokeMethod('configure', {
      'accessToken': accessToken,
      'customerId': customerId,
      'entryPoint': entryPoint,
      'environment': environment,
    });
  }

  /// Present the tokenization sheet and resolve with a token string.
  static Future<String> tokenize({required int type}) async {
    final result = await _channel.invokeMethod('tokenize', {'type': type}) as Map?;
    return (result?['token'] as String?) ?? '';
  }

  // MARK: - Internals

  static Future<dynamic> _handleCallback(MethodCall call) async {
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
}
