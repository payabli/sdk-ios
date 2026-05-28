import 'dart:async';

import 'package:flutter/material.dart';

import 'package:payabli_sdk/payabli_sdk.dart';

void main() => runApp(const PayabliFlutterDemoApp());

class PayabliFlutterDemoApp extends StatelessWidget {
  const PayabliFlutterDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Payabli TTP Demo',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _amountController = TextEditingController(
    text: '9.99',
  );
  final TextEditingController _activationController = TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController(
    text: '4111 1111 1111 1111',
  );
  final TextEditingController _cardExpController = TextEditingController(
    text: '02/25',
  );
  final TextEditingController _cardHolderController = TextEditingController(
    text: 'Jane Doe',
  );
  final TextEditingController _cardCvvController = TextEditingController(
    text: '123',
  );
  final TextEditingController _cardZipController = TextEditingController(
    text: '33139',
  );
  final TextEditingController _achAccountController = TextEditingController(
    text: '1111111111111',
  );
  final TextEditingController _achRoutingController = TextEditingController(
    text: '123456780',
  );
  final TextEditingController _achHolderController = TextEditingController(
    text: 'Jane Doe',
  );

  PayabliTTPSessionState _state = PayabliTTPSessionState.idle;
  String _lastResult = '';
  String _paymentMethodResult = '';
  final List<PayabliTTPEvent> _eventLog = [];
  StreamSubscription<PayabliTTPEvent>? _eventSub;
  bool _configured = false;
  bool _isWorking = false;
  bool _isSavingPaymentMethod = false;

  @override
  void initState() {
    super.initState();
    _configurePayabli();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _amountController.dispose();
    _activationController.dispose();
    _cardNumberController.dispose();
    _cardExpController.dispose();
    _cardHolderController.dispose();
    _cardCvvController.dispose();
    _cardZipController.dispose();
    _achAccountController.dispose();
    _achRoutingController.dispose();
    _achHolderController.dispose();
    super.dispose();
  }

  /// Configures `PayabliTTP` once at app launch with credentials from
  /// `Secrets`. In a real integration the access token comes from your
  /// backend's `/payabli/token` endpoint — never embed `clientSecret`
  /// in a mobile binary.
  Future<void> _configurePayabli() async {
    try {
      await PayabliTTP.configure(
        accessToken: await Secrets.fetchAccessToken(),
        tokenProvider: Secrets.fetchAccessToken,
        entryPoint: Secrets.entryPoint,
        appId: Secrets.appId,
        environment: PayabliEnvironment.sandbox,
      );
      await PayabliPaymentMethod.configure(
        accessTokenProvider: Secrets.fetchPaymentMethodAccessToken,
        entryPoint: Secrets.entryPoint,
        environment: PayabliEnvironment.sandbox,
      );
      _eventSub = PayabliTTP.events().listen(_onEvent);
      setState(() => _configured = true);
    } catch (e) {
      setState(() => _lastResult = 'Configure failed: $e');
    }
  }

  Future<void> _runAddCard() async {
    setState(() => _isSavingPaymentMethod = true);
    try {
      final method = await PayabliPaymentMethod.addCard(
        cardNumber: _cardNumberController.text,
        expiration: _cardExpController.text,
        cardholderName: _cardHolderController.text,
        cvv: _cardCvvController.text,
        billingZip: _cardZipController.text,
      );
      setState(() {
        _paymentMethodResult =
            "Stored method: ${method.storedMethodId ?? '—'}\n"
            'Response: ${method.responseText}\n'
            "Result: ${method.resultText ?? '—'}";
      });
    } on PayabliTTPException catch (e) {
      setState(() => _paymentMethodResult = '✗ ${e.code}: ${e.message}');
    } finally {
      setState(() => _isSavingPaymentMethod = false);
    }
  }

  Future<void> _runAddACH() async {
    setState(() => _isSavingPaymentMethod = true);
    try {
      final method = await PayabliPaymentMethod.addACH(
        accountNumber: _achAccountController.text,
        accountType: 'Checking',
        holderName: _achHolderController.text,
        routingNumber: _achRoutingController.text,
        secCode: 'WEB',
        holderType: 'personal',
      );
      setState(() {
        _paymentMethodResult =
            "Stored method: ${method.storedMethodId ?? '—'}\n"
            'Response: ${method.responseText}\n'
            "Result: ${method.resultText ?? '—'}";
      });
    } on PayabliTTPException catch (e) {
      setState(() => _paymentMethodResult = '✗ ${e.code}: ${e.message}');
    } finally {
      setState(() => _isSavingPaymentMethod = false);
    }
  }

  void _onEvent(PayabliTTPEvent event) {
    setState(() {
      _eventLog.insert(0, event);
      if (_eventLog.length > 100) _eventLog.removeLast();
    });
  }

  Future<void> _runInitialize() async {
    setState(() => _isWorking = true);
    try {
      await PayabliTTP.initialize();
      _state = await PayabliTTP.getSessionState();
      setState(() => _lastResult = '✓ Initialized');
    } on PayabliTTPException catch (e) {
      setState(() => _lastResult = '✗ ${e.code}: ${e.message}');
    } finally {
      setState(() => _isWorking = false);
    }
  }

  Future<void> _runCharge() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null) {
      setState(() => _lastResult = '✗ Invalid amount');
      return;
    }
    setState(() => _isWorking = true);
    try {
      final paymentTransId = await PayabliTTP.charge(
        paymentDetails: PayabliTTPPaymentDetails(amount: amount),
      );
      setState(() => _lastResult = '✓ Charged · txn $paymentTransId');
    } on PayabliTTPException catch (e) {
      setState(() => _lastResult = '✗ ${e.code}: ${e.message}');
    } finally {
      _state = await PayabliTTP.getSessionState();
      setState(() => _isWorking = false);
    }
  }

  Future<void> _runActivate() async {
    final code = _activationController.text.trim();
    if (code.isEmpty) return;
    Navigator.of(context).pop();
    _activationController.clear();

    setState(() => _isWorking = true);
    try {
      await PayabliTTP.activateDevice(activationCode: code);
      setState(() => _lastResult = '✓ Device activated');
    } on PayabliTTPException catch (e) {
      setState(() => _lastResult = '✗ ${e.code}: ${e.message}');
    } finally {
      setState(() => _isWorking = false);
    }
  }

  void _showActivationSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Activate device',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _activationController,
              decoration: const InputDecoration(
                labelText: 'Activation code',
                hintText: 'Code from Payabli ops',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _runActivate,
              child: const Text('Activate'),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Build

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Payabli Demo'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tap to Pay'),
              Tab(text: 'Payment Method'),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: _stateBadge(_state)),
            ),
          ],
        ),
        body: !_configured
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [_tapToPayContent(), _paymentMethodContent()],
              ),
      ),
    );
  }

  Widget _tapToPayContent() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Lifecycle', [
            FilledButton(
              onPressed: _isWorking || _state == PayabliTTPSessionState.ready
                  ? null
                  : _runInitialize,
              child: const Text('Initialize'),
            ),
            OutlinedButton(
              onPressed: _isWorking ? null : _showActivationSheet,
              child: const Text('Activate device…'),
            ),
          ]),
          const SizedBox(height: 16),
          _section('Sale', [
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: r'$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _isWorking || _state != PayabliTTPSessionState.ready
                  ? null
                  : _runCharge,
              child: const Text('Charge'),
            ),
          ]),
          const SizedBox(height: 16),
          _section(
              'Last result', [Text(_lastResult.isEmpty ? '—' : _lastResult)]),
          const SizedBox(height: 16),
          _section('Event log', [
            if (_eventLog.isEmpty)
              const Text('No events yet', style: TextStyle(color: Colors.grey))
            else
              ..._eventLog.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.code.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (e.payload.isNotEmpty)
                        Text(
                          e.payload.toString(),
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
          ]),
        ],
      );

  Widget _paymentMethodContent() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Card payment method', [
            TextField(
              controller: _cardNumberController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Card number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cardExpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Expiration',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cardHolderController,
              decoration: const InputDecoration(
                labelText: 'Name on card',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cardCvvController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'CVV',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cardZipController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ZIP code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _isSavingPaymentMethod ? null : _runAddCard,
              child: Text(_isSavingPaymentMethod ? 'Saving…' : 'Add card'),
            ),
          ]),
          const SizedBox(height: 16),
          _section('ACH payment method', [
            TextField(
              controller: _achAccountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Account number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _achRoutingController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Routing number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _achHolderController,
              decoration: const InputDecoration(
                labelText: 'Account holder',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _isSavingPaymentMethod ? null : _runAddACH,
              child: Text(_isSavingPaymentMethod ? 'Saving…' : 'Add ACH'),
            ),
          ]),
          const SizedBox(height: 16),
          _section('Payment Method result', [
            Text(
              _paymentMethodResult.isEmpty
                  ? 'No payment method result yet'
                  : _paymentMethodResult,
            ),
          ]),
        ],
      );

  Widget _section(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      );

  Widget _stateBadge(PayabliTTPSessionState s) {
    final color = switch (s) {
      PayabliTTPSessionState.ready => Colors.green,
      PayabliTTPSessionState.error ||
      PayabliTTPSessionState.sessionExpired =>
        Colors.red,
      PayabliTTPSessionState.pendingActivation => Colors.orange,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        s.name,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Demo-only secrets container. In production fetch the access token from
/// your backend — never embed clientSecret in the app binary.
class Secrets {
  static const String entryPoint = '<YOUR_ENTRY_POINT>';
  static const String appId = '<TEAM_ID>.<BUNDLE_ID>';

  static const String _tokenEndpoint =
      'https://your-backend.example.com/payabli/token';

  /// Replace with a real call to your backend. The mocked implementation
  /// below returns a placeholder so the app boots without network access
  /// — initialize() will fail with a clear error if the token is invalid.
  static Future<String> fetchAccessToken() async => 'placeholder-token';

  static Future<String> fetchPaymentMethodAccessToken() async =>
      'placeholder-payment-method-access-token';

  static String get tokenEndpoint => _tokenEndpoint;
}
