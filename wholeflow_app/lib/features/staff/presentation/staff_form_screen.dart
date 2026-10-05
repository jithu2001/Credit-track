import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/multi_picker_sheet.dart';
import '../../../core/widgets/states.dart';
import '../../company/domain/company.dart';
import '../../company/presentation/company_providers.dart';
import '../../sites/presentation/site_providers.dart';
import '../data/staff_repository.dart';
import '../domain/staff.dart';
import 'staff_providers.dart';

/// Add a staff member (userId == null) or edit name, companies and sites.
class StaffFormScreen extends ConsumerWidget {
  const StaffFormScreen({super.key, this.userId});

  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesProvider);
    final member = userId == null ? const AsyncData<StaffMember?>(null) : ref.watch(staffMemberProvider(userId!));
    final title = Text(userId == null ? 'Add staff' : 'Edit staff');
    return switch ((companies, member)) {
      (AsyncValue(value: final c?), AsyncValue(hasValue: true, value: final m)) =>
        userId != null && m == null
            ? Scaffold(
                appBar: AppBar(title: title),
                body: const EmptyState(icon: Icons.person_off_outlined, title: 'This staff member no longer exists'),
              )
            : _StaffForm(companies: c, existing: m),
      (AsyncValue(:final error?), _) || (_, AsyncValue(:final error?)) => Scaffold(
        appBar: AppBar(title: title),
        body: ErrorState(
          error: error,
          onRetry: () {
            ref.invalidate(companiesProvider);
            ref.invalidate(staffMembersProvider);
          },
        ),
      ),
      _ => Scaffold(
        appBar: AppBar(title: title),
        body: const SkeletonList(),
      ),
    };
  }
}

class _StaffForm extends ConsumerStatefulWidget {
  const _StaffForm({required this.companies, required this.existing});

  final List<Company> companies;
  final StaffMember? existing;

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  final _email = TextEditingController();
  final _password = TextEditingController(text: generatePassword());
  late final Map<String, CompanyGrant> _grants = {
    for (final a in widget.existing?.companies ?? const <CompanyAccess>[]) a.companyId: CompanyGrant.fromAccess(a),
  };
  late bool _checkIn = widget.existing?.requiresCheckIn ?? false;
  bool _companyError = false;
  bool _sitesError = false;
  bool _saving = false;

  bool get _isCreate => widget.existing == null;

  Map<String, String> get _companyNames => {for (final c in widget.companies) c.id: c.companyName};

  Map<String, String> get _siteNames => {for (final s in ref.read(allSitesProvider).value ?? const []) s.id: s.name};

  /// Grants in company-list order.
  List<CompanyGrant> get _orderedGrants => [
    for (final c in widget.companies)
      if (_grants[c.id] != null) _grants[c.id]!,
  ];

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    setState(() {
      _companyError = _isCreate && _grants.isEmpty;
      _sitesError = _grants.values.any((g) => g.needsSites);
    });
    if (!valid || _companyError || _sitesError) return;

    final grants = _orderedGrants;
    dismissKeyboard();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isCreate ? 'Create this account?' : 'Save changes?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(accessSummary(_name.text, grants, _companyNames, _siteNames)),
            const SizedBox(height: Insets.s),
            Text(_checkIn ? 'They must check in at shops on planned visit days.' : 'No shop check-in.'),
            if (!_isCreate && grants.isEmpty) ...[
              const SizedBox(height: Insets.m),
              Text('They can still sign in, but will see a "not assigned to any company" screen.', style: context.text.bodySmall),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_isCreate ? 'Create account' : 'Save')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final repo = ref.read(staffRepositoryProvider);
    try {
      if (_isCreate) {
        final email = _email.text.trim().toLowerCase();
        await repo.createStaff(
          name: _name.text.trim(),
          email: email,
          password: _password.text,
          companies: grants,
          requiresCheckIn: _checkIn,
        );
        ref.invalidate(staffMembersProvider);
        if (!mounted) return;
        await showCredentialsSheet(context, email: email, password: _password.text, title: 'Account created');
        if (mounted) context.pop();
      } else {
        final m = widget.existing!;
        if (_name.text.trim() != m.name.trim()) await repo.rename(m.id, _name.text.trim());
        final before = {for (final a in m.companies) a.companyId: CompanyGrant.fromAccess(a)};
        if (!_sameGrants(before, _grants)) await repo.setCompanies(m.id, grants);
        if (_checkIn != m.requiresCheckIn) await repo.setCheckIn(m.id, _checkIn);
        ref.invalidate(staffMembersProvider);
        if (!mounted) return;
        showMessage(context, 'Changes saved');
        context.pop();
      }
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static bool _sameGrants(Map<String, CompanyGrant> a, Map<String, CompanyGrant> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  Future<void> _pickSites(Company c) async {
    final grant = _grants[c.id]!;
    final picked = await showMultiPicker(
      context,
      (context) => Consumer(
        builder: (context, ref, _) {
          final sites = ref.watch(companySitesProvider(c.id));
          return MultiPickerSheet(
            title: 'Sites in ${c.companyName}',
            searchHint: 'Search sites',
            initial: grant.siteIds,
            options: sites.value == null ? null : [for (final s in sites.value!) (id: s.id, label: s.name)],
            error: sites.error,
            onRetry: () => ref.invalidate(companySitesProvider(c.id)),
            emptyIcon: Icons.location_city_outlined,
            emptyTitle: 'No sites in this company yet. Create them in the Sites tab.',
          );
        },
      ),
    );
    if (picked != null) {
      setState(() {
        _grants[c.id] = grant.copyWith(siteIds: picked);
        // Only clears here; the error first shows on submit.
        _sitesError = _sitesError && _grants.values.any((g) => g.needsSites);
      });
    }
  }

  Map<String, String> get _siteNamesWatched => {for (final s in ref.watch(allSitesProvider).value ?? const []) s.id: s.name};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isCreate ? 'Add staff' : 'Edit staff')),
      body: Form(
        key: _formKey,
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(Insets.l),
            children: [
              Text('Details', style: context.text.titleMedium),
              const SizedBox(height: Insets.m),
              TextFormField(
                key: const Key('staff-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: Insets.l),
              if (_isCreate) ...[
                TextFormField(
                  key: const Key('staff-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email (used to sign in)'),
                  validator: (v) =>
                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email',
                ),
                const SizedBox(height: Insets.l),
                TextFormField(
                  key: const Key('staff-password'),
                  controller: _password,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Initial password',
                    helperText: "They'll be asked to change it at first sign-in.",
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Generate password',
                          icon: const Icon(Icons.autorenew_rounded),
                          onPressed: () => setState(() => _password.text = generatePassword()),
                        ),
                        IconButton(
                          tooltip: 'Copy password',
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _password.text));
                            showMessage(context, 'Password copied');
                          },
                        ),
                      ],
                    ),
                  ),
                  validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
                ),
              ] else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.email_outlined),
                  title: Text(widget.existing!.email ?? ''),
                  subtitle: const Text('Sign-in email (cannot be changed)'),
                ),
              const SizedBox(height: Insets.xl),
              Text('Shop visits', style: context.text.titleMedium),
              SwitchListTile(
                key: const Key('staff-check-in'),
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.where_to_vote_outlined),
                title: const Text('Must check in at shops'),
                subtitle: const Text(
                  'On planned visit days they check in at each shop with GPS. Leave off for staff who do not visit shops.',
                ),
                value: _checkIn,
                onChanged: (v) => setState(() => _checkIn = v),
              ),
              const SizedBox(height: Insets.l),
              Text('Companies', style: context.text.titleMedium),
              const SizedBox(height: Insets.xs),
              Text(
                _isCreate
                    ? 'Choose at least one company this person works for. They will only see the companies you tick.'
                    : 'They will only see the companies you tick: the full company, or only the shops in the sites you choose.',
                style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              if (_sitesError) ...[
                const SizedBox(height: Insets.s),
                Text(
                  'Choose at least one site, or turn on Full company.',
                  key: const Key('sites-error'),
                  style: context.text.bodyMedium?.copyWith(color: context.colors.error),
                ),
              ],
              if (_companyError) ...[
                const SizedBox(height: Insets.s),
                Text(
                  'Select at least one company.',
                  key: const Key('company-error'),
                  style: context.text.bodyMedium?.copyWith(color: context.colors.error),
                ),
              ],
              const SizedBox(height: Insets.m),
              if (widget.companies.isEmpty)
                const Text('No companies have been synced from Tally yet.')
              else
                for (final c in widget.companies) ...[
                  _CompanyCard(
                    company: c,
                    grant: _grants[c.id],
                    onToggle: (on) => setState(() {
                      if (on) {
                        _grants[c.id] = CompanyGrant(companyId: c.id);
                        _companyError = false;
                      } else {
                        _grants.remove(c.id);
                      }
                    }),
                    siteNames: _siteNamesWatched,
                    onFullCompany: (v) => setState(() {
                      _grants[c.id] = _grants[c.id]!.copyWith(fullCompany: v);
                      // Only clears here; the error first shows on submit.
                      _sitesError = _sitesError && _grants.values.any((g) => g.needsSites);
                    }),
                    onPickSites: () => _pickSites(c),
                    onTransactions: (v) => setState(() => _grants[c.id] = _grants[c.id]!.copyWith(canViewTransactions: v)),
                  ),
                  const SizedBox(height: Insets.m),
                ],
              const SizedBox(height: Insets.l),
              FilledButton(
                key: const Key('staff-submit'),
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isCreate ? 'Review and create' : 'Review and save'),
              ),
              const SizedBox(height: Insets.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({
    required this.company,
    required this.grant,
    required this.onToggle,
    required this.siteNames,
    required this.onFullCompany,
    required this.onPickSites,
    required this.onTransactions,
  });

  final Company company;
  final CompanyGrant? grant;
  final ValueChanged<bool> onToggle;
  final Map<String, String> siteNames;
  final ValueChanged<bool> onFullCompany;
  final VoidCallback onPickSites;
  final ValueChanged<bool> onTransactions;

  @override
  Widget build(BuildContext context) {
    final g = grant;
    return Card.outlined(
      child: Column(
        children: [
          CheckboxListTile(value: g != null, title: Text(company.companyName), onChanged: (v) => onToggle(v ?? false)),
          if (g != null) ...[
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.domain_outlined),
              title: const Text('Full company'),
              subtitle: Text(g.fullCompany ? 'Every shop, including shops in no site' : 'Only the shops in the sites below'),
              value: g.fullCompany,
              onChanged: onFullCompany,
            ),
            if (!g.fullCompany)
              ListTile(
                leading: const Icon(Icons.location_city_outlined),
                title: const Text('Sites'),
                subtitle: Text(
                  g.siteIds.isEmpty
                      ? 'Choose sites'
                      : (g.siteIds.map((id) => siteNames[id] ?? 'Removed site').toList()
                              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
                            .join(', '),
                  style: g.siteIds.isEmpty ? TextStyle(color: context.colors.error) : null,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onPickSites,
              ),
            SwitchListTile(
              secondary: const Icon(Icons.receipt_long_outlined),
              title: const Text('Can view transactions'),
              value: g.canViewTransactions,
              onChanged: onTransactions,
            ),
          ],
        ],
      ),
    );
  }
}

/// One-time sheet with sign-in details for the owner to pass on.
Future<void> showCredentialsSheet(
  BuildContext context, {
  required String email,
  required String password,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: context.text.titleLarge),
            const SizedBox(height: Insets.s),
            Text(
              "Share these sign-in details with the staff member. The password won't be shown again.",
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: Insets.l),
            _CopyRow(label: 'Email', value: email),
            _CopyRow(label: 'Password', value: password),
            const SizedBox(height: Insets.l),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_all_rounded),
              label: const Text('Copy both'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: 'WholeFlow sign-in\nEmail: $email\nPassword: $password'));
                showMessage(context, 'Sign-in details copied');
              },
            ),
            const SizedBox(height: Insets.s),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      ),
    ),
  );
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: SelectableText(value, style: context.text.titleMedium),
      subtitle: Text(label),
      trailing: IconButton(
        tooltip: 'Copy $label',
        icon: const Icon(Icons.copy_rounded),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: value));
          showMessage(context, '$label copied');
        },
      ),
    );
  }
}
