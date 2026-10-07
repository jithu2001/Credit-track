import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../company/domain/company.dart';
import '../domain/visit.dart';
import 'visit_providers.dart';
import 'visit_widgets.dart';

/// Owner: one day of planned visits in the active company, by staff member.
class VisitsView extends ConsumerWidget {
  const VisitsView({super.key, required this.company});

  final Company company;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(visitDayControllerProvider);
    final tasks = ref.watch(companyDayTasksProvider(company.id, day));
    final dayCtl = ref.read(visitDayControllerProvider.notifier);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(companyDayTasksProvider(company.id, day).future),
      child: ContentWidth(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.s, Insets.xs, Insets.l, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous day',
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () => dayCtl.shift(-1),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: day,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 60)),
                        );
                        if (picked != null) dayCtl.set(picked);
                      },
                      child: Text(dayLabel(day), style: context.text.titleMedium),
                    ),
                    IconButton(
                      tooltip: 'Next day',
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () => dayCtl.shift(1),
                    ),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      key: const Key('visit-plans'),
                      onPressed: () => context.push('/visits/plans'),
                      icon: const Icon(Icons.event_note_outlined),
                      label: const Text('Plans'),
                    ),
                  ],
                ),
              ),
            ),
            ...switch (tasks) {
              AsyncValue(:final value?) when value.isEmpty => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: Insets.xl),
                    child: EmptyState(
                      icon: Icons.event_available_outlined,
                      title: 'No visits planned for ${dayLabel(day).toLowerCase()}',
                      message: 'Plan a site for staff who check in at shops.',
                      action: FilledButton(onPressed: () => context.push('/visits/plans/new'), child: const Text('Plan visits')),
                    ),
                  ),
                ),
              ],
              AsyncValue(:final value?) => _byStaff(context, value),
              AsyncValue(:final error?) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: Insets.xl),
                    child: ErrorState(error: error, onRetry: () => ref.invalidate(companyDayTasksProvider(company.id, day))),
                  ),
                ),
              ],
              _ => [SliverList.list(children: List.filled(4, const SkeletonTile()))],
            },
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  List<Widget> _byStaff(BuildContext context, List<VisitTask> tasks) {
    final byStaff = <String, List<VisitTask>>{};
    for (final t in tasks) {
      byStaff.putIfAbsent(t.staffId, () => []).add(t);
    }
    final all = DayProgress(tasks);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.m),
          child: Text(
            [
              '${all.visited} of ${plural(all.total, 'shop')} visited',
              if (all.missed > 0) '${all.missed} missed',
              if (all.pending > 0) '${all.pending} to go',
            ].join(' · '),
            style: context.text.bodyMedium,
          ),
        ),
      ),
      for (final e in byStaff.entries)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.m),
            child: _StaffDayCard(tasks: e.value),
          ),
        ),
    ];
  }
}

class _StaffDayCard extends StatelessWidget {
  const _StaffDayCard({required this.tasks});

  final List<VisitTask> tasks;

  @override
  Widget build(BuildContext context) {
    final p = DayProgress(tasks);
    final name = tasks.first.staffName.isEmpty ? 'Staff' : tasks.first.staffName;
    final sites = {for (final t in tasks) t.siteName}.join(', ');
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        title: Text(name, style: context.text.titleMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${p.visited} of ${p.total} visited · $sites', maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Insets.xs),
            LinearProgressIndicator(value: p.total == 0 ? 0 : p.visited / p.total, borderRadius: BorderRadius.circular(4)),
          ],
        ),
        children: [
          for (final t in tasks)
            VisitTaskTile(
              task: t,
              showSite: sites.contains(','),
              onTap: () => context.push('/visits/task', extra: t),
            ),
        ],
      ),
    );
  }
}
