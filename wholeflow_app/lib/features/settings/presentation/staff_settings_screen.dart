import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../auth/presentation/session_controller.dart';
import 'settings_screen.dart';
import 'theme_controller.dart';

class StaffSettingsScreen extends ConsumerWidget {
  const StaffSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold();
    final business = ref.watch(businessNameProvider).value;
    final theme = ref.watch(themeControllerProvider);
    final version = ref.watch(appVersionProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: Insets.s),
          children: [
            ListTile(
              leading: CircleAvatar(child: Text(user.displayName.characters.first.toUpperCase())),
              title: Text(user.displayName),
              subtitle: Text([user.role.label, ?business, if (user.email != null) user.email!].join(' · ')),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.s),
              child: Text('Appearance', style: context.text.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.l),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_outlined)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {theme},
                onSelectionChanged: (s) => ref.read(themeControllerProvider.notifier).set(s.first),
              ),
            ),
            const SizedBox(height: Insets.m),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('Change password'),
              onTap: () => _changePassword(context),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out'),
              onTap: () => _confirmSignOut(context, ref),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('WholeFlow Staff'),
              subtitle: Text(version == null ? 'Version' : 'Version $version'),
            ),
          ],
        ),
      ),
    );
  }

  void _changePassword(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SafeArea(child: ChangePasswordSheet()),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to enter your email and password to sign back in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(sessionControllerProvider.notifier).signOut();
    }
  }
}
