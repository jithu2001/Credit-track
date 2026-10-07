import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/presentation/company_providers.dart';
import '../../sites/domain/site.dart';
import '../../sites/presentation/site_providers.dart';
import '../../staff/domain/staff.dart';
import '../../staff/presentation/staff_providers.dart';
import '../data/visit_repository.dart';
import '../domain/visit.dart';
import 'visit_providers.dart';

final _date = DateFormat('d MMM yyyy');

String describePlan(VisitPlan p) {
  if (!p.weekly) return 'On ${_date.format(p.planDate!)}';
  final from = p.startsOn == null ? '' : ' from ${_date.format(p.startsOn!)}';
  final until = p.endsOn == null ? '' : ' until ${_date.format(p.endsOn!)}';
  return 'Every ${weekdayNames[p.weekday! - 1]}$from$until';
}

/// Owner: who visits which site when, in the active company.
class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(activeCompanyProvider).value;
    final plans = company == null ? null : ref.watch(visitPlansProvider(company.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Visit plans')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-plan'),
        onPressed: () => context.push('/visits/plans/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Plan visits'),
      ),
      body: switch (plans) {
        null => const SizedBox.shrink(),
        AsyncValue(:final value?) when value.isEmpty => const EmptyState(
          icon: Icons.event_note_outlined,
          title: 'No visit plans yet',
          message: 'Plan a site for a staff member on a date, or every week.',
        ),
        AsyncValue(:final value?) => ContentWidth(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: value.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: Insets.l),
            itemBuilder: (context, i) => _PlanTile(plan: value[i], companyId: company!.id),
          ),
        ),
        AsyncValue(:final error?) => ErrorState(error: error, onRetry: () => ref.invalidate(visitPlansProvider(company!.id))),
        _ => const SkeletonList(),
      },
    );
  }
}

class _PlanTile extends ConsumerWidget {
  const _PlanTile({required this.plan, required this.companyId});

  final VisitPlan plan;
  final String companyId;

  void _changed(WidgetRef ref) => ref
    ..invalidate(visitPlansProvider(companyId))
    ..invalidate(companyDayTasksProvider);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(visitRepositoryProvider);
    return ListTile(
      title: Text('${plan.staffName ?? 'Staff'} · ${plan.siteName ?? 'Site'}'),
      subtitle: Text(plan.active ? describePlan(plan) : '${describePlan(plan)} · paused'),
      leading: Icon(plan.weekly ? Icons.repeat_rounded : Icons.event_outlined),
      trailing: PopupMenuButton<String>(
        tooltip: 'Plan options',
        onSelected: (v) async {
          try {
            if (v == 'pause') await repo.setPlanActive(plan.id, !plan.active);
            if (v == 'delete') await repo.deletePlan(plan.id);
            _changed(ref);
          } on AppFailure catch (f) {
            if (context.mounted) showMessage(context, f.message);
          }
        },
        itemBuilder: (context) => [
          if (plan.weekly) PopupMenuItem(value: 'pause', child: Text(plan.active ? 'Pause' : 'Resume')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

/// Owner: plan a site for a staff member who checks in, on one day or weekly.
class PlanEditorScreen extends ConsumerStatefulWidget {
  const PlanEditorScreen({super.key});

  @override
  ConsumerState<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends ConsumerState<PlanEditorScreen> {
  String? _staffId;
  String? _siteId;
  bool _weekly = false;
  DateTime _date = DateTime.now();
  final Set<int> _weekdays = {};
  DateTime _startsOn = DateTime.now();
  DateTime? _endsOn;
  bool _saving = false;

  Future<DateTime?> _pick(DateTime initial, {DateTime? first}) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first ?? DateTime.now().subtract(const Duration(days: 1)),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  );

  /// Sites in this company the staff member can visit: all of them with the
  /// full company, otherwise their chosen sites.
  List<Site> _sitesFor(StaffMember? m, List<Site> sites, String companyId) {
    if (m == null) return const [];
    final access = m.companies.where((a) => a.companyId == companyId).firstOrNull;
    if (access == null) return const [];
    return access.fullCompany ? sites : sites.where((s) => access.siteIds.contains(s.id)).toList();
  }

  Future<void> _save(String companyId) async {
    if (_staffId == null || _siteId == null || (_weekly && _weekdays.isEmpty)) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(visitRepositoryProvider)
          .createPlans(
            siteId: _siteId!,
            staffId: _staffId!,
            date: _weekly ? null : _date,
            weekdays: _weekly ? _weekdays : const {},
            startsOn: _startsOn,
            endsOn: _endsOn,
          );
      ref
        ..invalidate(visitPlansProvider(companyId))
        ..invalidate(companyDayTasksProvider);
      if (!mounted) return;
      showMessage(context, 'Visits planned');
      context.pop();
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(activeCompanyProvider).value;
    final staff = ref.watch(staffMembersProvider);
    final sites = company == null ? null : ref.watch(companySitesProvider(company.id));
    if (company == null) return Scaffold(appBar: AppBar(title: const Text('Plan visits')));
    final checkers = [
      for (final m in staff.value ?? const <StaffMember>[])
        if (!m.isOwner && m.isActive && m.requiresCheckIn && m.companies.any((a) => a.companyId == company.id)) m,
    ];
    final member = checkers.where((m) => m.id == _staffId).firstOrNull;
    final siteOptions = _sitesFor(member, sites?.value ?? const [], company.id);
    if (_siteId != null && !siteOptions.any((s) => s.id == _siteId)) _siteId = null;
    final ready = _staffId != null && _siteId != null && (!_weekly || _weekdays.isNotEmpty);
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Plan visits')),
      body: staff.isLoading || (sites?.isLoading ?? true)
          ? const SkeletonList()
          : ContentWidth(
              child: ListView(
                padding: const EdgeInsets.all(Insets.l),
                children: [
                  if (checkers.isEmpty)
                    Card.filled(
                      color: context.semantic.warningContainer,
                      child: ListTile(
                        leading: Icon(Icons.info_outline_rounded, color: context.semantic.onWarningContainer),
                        title: Text(
                          'No staff check in at shops in ${company.companyName}. '
                          'Turn on "Must check in at shops" for a staff member in Settings → Staff.',
                          style: TextStyle(color: context.semantic.onWarningContainer),
                        ),
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    key: const Key('plan-staff'),
                    initialValue: _staffId,
                    decoration: const InputDecoration(labelText: 'Staff member'),
                    items: [for (final m in checkers) DropdownMenuItem(value: m.id, child: Text(m.displayName))],
                    onChanged: (v) => setState(() => _staffId = v),
                  ),
                  const SizedBox(height: Insets.l),
                  DropdownButtonFormField<String>(
                    key: ValueKey('plan-site-$_staffId'),
                    initialValue: _siteId,
                    decoration: InputDecoration(
                      labelText: 'Site',
                      helperText: member != null && siteOptions.isEmpty ? 'This staff member has no sites here yet.' : null,
                    ),
                    items: [for (final s in siteOptions) DropdownMenuItem(value: s.id, child: Text(s.name))],
                    onChanged: member == null ? null : (v) => setState(() => _siteId = v),
                  ),
                  const SizedBox(height: Insets.xl),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('One day'), icon: Icon(Icons.event_outlined)),
                      ButtonSegment(value: true, label: Text('Every week'), icon: Icon(Icons.repeat_rounded)),
                    ],
                    selected: {_weekly},
                    onSelectionChanged: (s) => setState(() => _weekly = s.first),
                  ),
                  const SizedBox(height: Insets.l),
                  if (!_weekly)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: Text(_fmt(_date)),
                      subtitle: const Text('Visit date'),
                      onTap: () async {
                        final d = await _pick(_date);
                        if (d != null) setState(() => _date = d);
                      },
                    )
                  else ...[
                    Text('On', style: context.text.titleSmall),
                    const SizedBox(height: Insets.s),
                    Wrap(
                      spacing: Insets.s,
                      runSpacing: Insets.s,
                      children: [
                        for (var w = 1; w <= 7; w++)
                          FilterChip(
                            label: Text(weekdayNames[w - 1].substring(0, 3)),
                            selected: _weekdays.contains(w),
                            onSelected: (on) => setState(() => on ? _weekdays.add(w) : _weekdays.remove(w)),
                          ),
                      ],
                    ),
                    const SizedBox(height: Insets.s),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_arrow_outlined),
                      title: Text(_fmt(_startsOn)),
                      subtitle: const Text('Starts'),
                      onTap: () async {
                        final d = await _pick(_startsOn);
                        if (d != null) setState(() => _startsOn = d);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.stop_outlined),
                      title: Text(_endsOn == null ? 'No end date' : _fmt(_endsOn!)),
                      subtitle: const Text('Ends (optional)'),
                      trailing: _endsOn == null
                          ? null
                          : IconButton(
                              tooltip: 'Clear end date',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() => _endsOn = null),
                            ),
                      onTap: () async {
                        final d = await _pick(_endsOn ?? _startsOn, first: _startsOn);
                        if (d != null) setState(() => _endsOn = d);
                      },
                    ),
                  ],
                  const SizedBox(height: Insets.m),
                  Text(
                    'On the day, the staff member must check in at every shop in the site. Shops left unvisited show as missed.',
                    style: muted,
                  ),
                  const SizedBox(height: Insets.xl),
                  FilledButton(
                    key: const Key('save-plan'),
                    onPressed: !ready || _saving ? null : () => _save(company.id),
                    child: const Text('Save plan'),
                  ),
                ],
              ),
            ),
    );
  }
}

String _fmt(DateTime d) => _date.format(d);
