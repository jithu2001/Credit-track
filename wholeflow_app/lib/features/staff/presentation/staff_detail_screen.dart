import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/domain/company.dart';
import '../../company/presentation/company_providers.dart';
import '../data/staff_repository.dart';
import '../domain/staff.dart';
import 'staff_form_screen.dart';
import 'staff_providers.dart';

class StaffDetailScreen extends ConsumerWidget {
  const StaffDetailScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(staffMemberProvider(userId));
    final companies = ref.watch(companiesProvider).value ?? const <Company>[];
    return switch (member) {
      AsyncValue(hasValue: true, value: final m) when m == null => Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.person_off_outlined, title: 'This account no longer exists'),
      ),
      AsyncValue(value: final m?) => _Loaded(member: m, companies: companies),
      AsyncValue(:final error?) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(error: error, onRetry: () => ref.invalidate(staffMembersProvider)),
      ),
      _ => Scaffold(appBar: AppBar(), body: const SkeletonList()),
    };
  }
}

class _Loaded extends ConsumerStatefulWidget {
  const _Loaded({required this.member, required this.companies});

  final StaffMember member;
  final List<Company> companies;

  @override
  ConsumerState<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends ConsumerState<_Loaded> {
  bool _busy = false;

  StaffMember get m => widget.member;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(staffMembersProvider);
      if (mounted) showMessage(context, done);
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive() async {
    final disabling = m.isActive;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(disabling ? 'Disable ${m.displayName}?' : 'Enable ${m.displayName}?'),
        content: Text(
          disabling
              ? "They will be signed out and won't be able to sign in until you enable the account again."
              : 'They will be able to sign in again with their current password.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(disabling ? 'Disable' : 'Enable')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(staffRepositoryProvider).setActive(m.id, !disabling),
      disabling ? 'Account disabled' : 'Account enabled',
    );
  }

  Future<void> _resetPassword() async {
    final password = generatePassword();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset password?'),
        content: Text('${m.displayName} will get a new password and must change it at next sign-in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(staffRepositoryProvider).resetPassword(m.id, password);
      if (mounted) await showCredentialsSheet(context, email: m.email ?? '', password: password, title: 'New password set');
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = {for (final c in widget.companies) c.id: c.companyName};
    return Scaffold(
      appBar: AppBar(
        title: Text(m.displayName),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(Insets.l),
          children: [
            Card.filled(
              child: Column(
                children: [
                  ListTile(leading: const Icon(Icons.badge_outlined), title: Text(m.role.label), subtitle: const Text('Role')),
                  if (m.email != null)
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: Text(m.email!),
                      subtitle: const Text('Sign-in email'),
                    ),
                  ListTile(
                    leading: Icon(m.isActive ? Icons.check_circle_outline : Icons.block_rounded),
                    title: Text(m.isActive ? 'Active' : 'Disabled'),
                    subtitle: const Text('Status'),
                  ),
                  if (m.createdAt != null)
                    ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: Text(formatDate(m.createdAt!.toLocal())),
                      subtitle: const Text('Added'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Insets.xl),
            Text('Companies', style: context.text.titleMedium),
            const SizedBox(height: Insets.s),
            if (m.isOwner)
              const Card.outlined(
                child: ListTile(title: Text('All companies'), subtitle: Text('Owners see every company.')),
              )
            else if (m.companies.isEmpty)
              Card.filled(
                color: context.semantic.warningContainer,
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded, color: context.semantic.onWarningContainer),
                  title: Text('No company assigned', style: TextStyle(color: context.semantic.onWarningContainer)),
                  subtitle: Text(
                    "They can sign in but can't see any data.",
                    style: TextStyle(color: context.semantic.onWarningContainer),
                  ),
                ),
              )
            else
              Card.outlined(
                child: Column(
                  children: [
                    for (final a in m.companies)
                      ListTile(
                        leading: const Icon(Icons.business_outlined),
                        title: Text(names[a.companyId] ?? 'Company'),
                        subtitle: Text(describeGrant(CompanyGrant.fromAccess(a))),
                      ),
                  ],
                ),
              ),
            if (m.isOwner) ...[
              const SizedBox(height: Insets.l),
              Text(
                'Owner accounts are managed by your administrator.',
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ] else ...[
              const SizedBox(height: Insets.xl),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => context.push('/staff/${m.id}/edit'),
                icon: const Icon(Icons.business_center_outlined),
                label: const Text('Change companies or name'),
              ),
              const SizedBox(height: Insets.s),
              OutlinedButton.icon(
                onPressed: _busy ? null : _resetPassword,
                icon: const Icon(Icons.password_rounded),
                label: const Text('Reset password'),
              ),
              const SizedBox(height: Insets.s),
              OutlinedButton.icon(
                onPressed: _busy ? null : _toggleActive,
                icon: Icon(m.isActive ? Icons.block_rounded : Icons.check_circle_outline),
                label: Text(m.isActive ? 'Disable account' : 'Enable account'),
                style: m.isActive ? OutlinedButton.styleFrom(foregroundColor: context.colors.error) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
