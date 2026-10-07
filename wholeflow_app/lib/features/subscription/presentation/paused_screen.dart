import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/business_connection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/phone_tile.dart';
import '../../auth/presentation/session_controller.dart';

/// Full-screen block once the business's subscription has ended or was
/// suspended. No data is shown (the server refuses it anyway); Refresh
/// re-checks, so recording a payment unblocks the app without a reinstall.
class PausedScreen extends ConsumerStatefulWidget {
  const PausedScreen({super.key, required this.forOwner});

  final bool forOwner;

  @override
  ConsumerState<PausedScreen> createState() => _PausedScreenState();
}

class _PausedScreenState extends ConsumerState<PausedScreen> with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from paying (or from WhatsApp): check again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionControllerProvider.notifier).retry();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).value;
    final paused = session is Paused ? session : const Paused();
    final connection = ref.watch(businessConnectionProvider);
    final contact = paused.contact;
    final isPhone = contact != null && RegExp(r'\d').allMatches(contact).length >= 10 && !contact.contains('@');
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.pause_circle_outline_rounded, size: 64, color: context.colors.error),
                  const SizedBox(height: Insets.l),
                  Text(
                    widget.forOwner ? 'Subscription ended' : 'WholeFlow is paused',
                    key: const Key('paused-title'),
                    style: context.text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  if (connection.businessName.isNotEmpty) ...[
                    const SizedBox(height: Insets.xs),
                    Text(
                      connection.businessName,
                      style: context.text.titleMedium?.copyWith(color: context.colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: Insets.l),
                  Text(
                    widget.forOwner
                        ? (paused.message ?? 'The WholeFlow subscription for this business has ended. Renew it to continue.')
                        : 'WholeFlow is paused for this business. Ask your owner to renew the subscription.',
                    style: context.text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (widget.forOwner && contact != null) ...[
                    const SizedBox(height: Insets.l),
                    Card.outlined(
                      child: isPhone
                          ? PhoneTile(phone: contact)
                          : ListTile(leading: const Icon(Icons.support_agent_rounded), title: SelectableText(contact)),
                    ),
                  ],
                  const SizedBox(height: Insets.xl),
                  FilledButton.icon(
                    key: const Key('paused-refresh'),
                    onPressed: _busy ? null : _refresh,
                    icon: _busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh'),
                  ),
                  const SizedBox(height: Insets.s),
                  Text(
                    widget.forOwner ? 'After paying, tap Refresh. Your data is safe.' : 'Your data is safe.',
                    style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Insets.l),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
                        child: const Text('Sign out'),
                      ),
                      TextButton(onPressed: () => confirmSwitchBusiness(context, ref), child: const Text('Switch business')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks, then closes this business and shows the connect screen.
Future<void> confirmSwitchBusiness(BuildContext context, WidgetRef ref) async {
  final name = ref.read(businessConnectionProvider).businessName;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Switch business?'),
      content: Text(
        'You will be signed out${name.isEmpty ? '' : ' of $name'}. '
        'You need the other business\'s reference key to connect.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Switch')),
      ],
    ),
  );
  if (ok == true) await ref.read(switchBusinessProvider)();
}
