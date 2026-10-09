import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../theme/app_theme.dart';
import 'upgrade_gate.dart';

/// Wraps the whole app (`MaterialApp.router(builder: …)`): once the server
/// says this version is too old, only [UpdateRequiredScreen] is shown, on top
/// of whatever screen was open, until the app is updated.
class UpdateRequiredFrame extends StatelessWidget {
  const UpdateRequiredFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: UpgradeGate.message,
      builder: (context, message, child) => message == null
          ? child!
          : Stack(
              children: [
                // Kept (but hidden and inert) so the app's state survives.
                Offstage(child: child),
                Positioned.fill(child: UpdateRequiredScreen(message: message)),
              ],
            ),
      child: child,
    );
  }
}

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.message});

  final String message;

  static Future<void> openStore() async {
    final id = AppInfo.current.packageId;
    if (AppInfo.current.platform == 'android') {
      try {
        if (await launchUrl(Uri.parse('market://details?id=$id'), mode: LaunchMode.externalApplication)) return;
      } catch (_) {
        // No Play Store app: the web page below.
      }
    }
    try {
      await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=$id'), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing can open it; the text says what to do.
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('update-required'),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Insets.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.system_update_rounded, size: 64, color: context.colors.primary),
                    const SizedBox(height: Insets.l),
                    Text('Update required', style: context.text.headlineSmall, textAlign: TextAlign.center),
                    const SizedBox(height: Insets.m),
                    Text(message, style: context.text.bodyLarge, textAlign: TextAlign.center),
                    const SizedBox(height: Insets.xl),
                    if (AppInfo.current.platform == 'android')
                      FilledButton.icon(
                        key: const Key('update-open-store'),
                        onPressed: openStore,
                        icon: const Icon(Icons.shop_rounded),
                        label: const Text('Update on Google Play'),
                      )
                    else
                      Text(
                        'Update WholeFlow from the App Store, then open it again.',
                        style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
