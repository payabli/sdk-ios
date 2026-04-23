import 'package:flutter/material.dart';
import 'package:payabli_sdk/payabli_sdk.dart';

/// Replace with your own backend endpoint that mints a Payabli access token
/// server-side (never ship the clientSecret in the app binary).
Future<String> fetchAccessTokenFromPartnerBackend() async {
  // TODO: implement HTTP call to your backend. Stubbed for scaffolding.
  throw UnimplementedError('Wire me to your backend.');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final token = await fetchAccessTokenFromPartnerBackend();
  await PayabliSDK.configure(
    accessToken: token,
    tokenProvider: fetchAccessTokenFromPartnerBackend,
    entryPoint: '<YOUR_ENTRY_POINT>',
    environment: PayabliSDK.envSandbox,
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String lastResult = '—';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('PayabliSDK Flutter Demo')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ElevatedButton(
                onPressed: () async {
                  try {
                    final tok = await PayabliSDK.tokenize(
                      type: PayabliSDK.typeCard,
                      customerId: 4440,
                    );
                    setState(() => lastResult = 'Token: $tok');
                  } catch (e) {
                    setState(() => lastResult = 'Error: $e');
                  }
                },
                child: const Text('Tokenize card'),
              ),
              const SizedBox(height: 16),
              Text(lastResult),
            ],
          ),
        ),
      ),
    );
  }
}
