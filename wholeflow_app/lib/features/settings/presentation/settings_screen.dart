import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/password_form.dart';
import '../../auth/presentation/session_controller.dart';
import 'theme_controller.dart';

part 'settings_screen.g.dart';

@riverpod
Future<String?> businessName(Ref ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(authRepositoryProvider).businessName(user.businessId);
}

@riverpod
Future<String> appVersion(Ref ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

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
            if (user.isOwner)
              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: const Text('Staff'),
                subtitle: const Text('Accounts, companies and areas'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/staff'),
              ),
            if (user.isOwner)
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Sync health'),
                subtitle: const Text('Tally PC, companies and recent sync runs'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/sync-health'),
              ),
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
              title: const Text('WholeFlow'),
              subtitle: Text(version == null ? 'Version' : 'Version $version'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => const _ChangePasswordSheet(),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await ref.read(sessionControllerProvider.notifier).signOut();
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  bool _busy = false;

  Future<void> _submit(String password) async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionControllerProvider.notifier).changePassword(password);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'Password changed');
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Change password', style: context.text.titleLarge),
            const SizedBox(height: Insets.l),
            NewPasswordForm(onSubmit: _submit, submitLabel: 'Change password', busy: _busy),
          ],
        ),
      ),
    );
  }
}
