import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../errors/app_failure.dart';
import '../theme/app_theme.dart';
import 'business_connection.dart';

/// The WholeFlow website: what it is, plans, and how to get started.
const wholeflowWebsite = 'https://wholeflow.jitsuji.xyz/';

/// The app before a business is chosen: one screen that turns a reference key
/// into a saved connection.
class ConnectApp extends StatelessWidget {
  const ConnectApp({super.key, required this.title, required this.onConnected, this.api});

  final String title;
  final Future<void> Function(BusinessConnection connection) onConnected;
  final ControlApi? api;

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (light, dark) => MaterialApp(
        title: title,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(light),
        darkTheme: AppTheme.dark(dark),
        home: ConnectScreen(title: title, onConnected: onConnected, api: api),
      ),
    );
  }
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.title, required this.onConnected, this.api});

  final String title;
  final Future<void> Function(BusinessConnection connection) onConnected;
  final ControlApi? api;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _key = TextEditingController();
  late final ControlApi _api = widget.api ?? ControlApi();
  bool _busy = false;
  String? _error;

  /// The business found for the key, waiting for "Connect".
  BusinessConnection? _found;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _openWebsite() async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(wholeflowWebsite), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && mounted) setState(() => _error = 'Could not open the browser. Visit $wholeflowWebsite');
  }

  Future<void> _lookUp() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await _api.connect(_key.text);
      if (mounted) setState(() => _found = c);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await widget.onConnected(_found!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppFailure.from(e).message;
        });
      }
    }
  }

  Future<void> _scan() async {
    final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScanScreen()));
    if (value == null || !mounted) return;
    _key.text = value;
    await _lookUp();
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.account_balance_wallet_rounded, size: 56, color: context.colors.primary),
                  const SizedBox(height: Insets.l),
                  Text(widget.title, style: context.text.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: Insets.xxl),
                  if (found == null) ...[
                    Text('Connect to your business', style: context.text.titleLarge),
                    const SizedBox(height: Insets.xs),
                    Text(
                      'Enter the reference key your business owner or WholeFlow support gave you, or scan its QR code.',
                      style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: Insets.xl),
                    if (_error != null) ...[_ErrorCard(_error!), const SizedBox(height: Insets.l)],
                    TextField(
                      key: const Key('connect-key'),
                      controller: _key,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _busy ? null : _lookUp(),
                      style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1),
                      decoration: const InputDecoration(
                        labelText: 'Reference key',
                        hintText: 'ABCD-1234-EFGH-5678',
                        prefixIcon: Icon(Icons.key_rounded),
                      ),
                    ),
                    const SizedBox(height: Insets.xl),
                    FilledButton(
                      key: const Key('connect-continue'),
                      onPressed: _busy ? null : _lookUp,
                      child: _busy
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Continue'),
                    ),
                    const SizedBox(height: Insets.m),
                    OutlinedButton.icon(
                      key: const Key('connect-scan'),
                      onPressed: _busy ? null : _scan,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Scan QR code'),
                    ),
                    const SizedBox(height: Insets.xxl),
                    Text("Don't have a key?", style: context.text.titleSmall, textAlign: TextAlign.center),
                    const SizedBox(height: Insets.xs),
                    Text(
                      'Staff: ask your business owner for it. Business owners: see how to get started with WholeFlow at',
                      style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    TextButton.icon(
                      key: const Key('connect-website'),
                      onPressed: _openWebsite,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('wholeflow.jitsuji.xyz'),
                    ),
                  ] else ...[
                    Text('Connect to', style: context.text.titleMedium, textAlign: TextAlign.center),
                    const SizedBox(height: Insets.s),
                    Text(
                      found.businessName,
                      key: const Key('connect-business-name'),
                      style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Insets.s),
                    Text(
                      'You will sign in with the account this business gave you.',
                      style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Insets.xl),
                    if (_error != null) ...[_ErrorCard(_error!), const SizedBox(height: Insets.l)],
                    FilledButton(
                      key: const Key('connect-confirm'),
                      onPressed: _busy ? null : _connect,
                      child: _busy
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Connect'),
                    ),
                    const SizedBox(height: Insets.m),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _found = null),
                      child: const Text('Use a different key'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      key: const Key('connect-error'),
      color: context.colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(Insets.m),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: context.colors.onErrorContainer),
            const SizedBox(width: Insets.m),
            Expanded(
              child: Text(message, style: TextStyle(color: context.colors.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Camera view that returns the first QR code that holds a reference key.
class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && normalizeReferenceKey(raw) != null) {
        _done = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan reference key')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(Insets.xl),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Allow camera access in Settings to scan, or go back and type the key.'
                      : "The camera couldn't start. Go back and type the key.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(Insets.xl),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(Insets.m),
                  child: Text('Point the camera at the QR code', style: context.text.bodyMedium),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
