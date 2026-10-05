import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../home/account_button.dart';
import '../domain/visit.dart';
import 'visit_providers.dart';
import 'visit_widgets.dart';

/// Staff tab (only for staff who check in): today's shops, then history.
class StaffVisitsScreen extends ConsumerStatefulWidget {
  const StaffVisitsScreen({super.key});

  @override
  ConsumerState<StaffVisitsScreen> createState() => _StaffVisitsScreenState();
}

class _StaffVisitsScreenState extends ConsumerState<StaffVisitsScreen> {
  bool _history = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visits'), actions: const [AccountButton()]),
      body: Column(
        children: [
          ContentWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.s),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Today')),
                    ButtonSegment(value: true, label: Text('History')),
                  ],
                  selected: {_history},
                  onSelectionChanged: (s) => setState(() => _history = s.first),
                ),
              ),
            ),
          ),
          Expanded(child: _history ? const _History() : const _Today()),
        ],
      ),
    );
  }
}

class _Today extends ConsumerWidget {
  const _Today();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(myTodayTasksProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(myTodayTasksProvider.future),
      child: switch (tasks) {
        AsyncValue(:final value?) when value.isEmpty => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: Insets.xxl),
            EmptyState(
              icon: Icons.event_available_outlined,
              title: 'No shop visits today',
              message: 'When your owner plans a site for you, its shops show here.',
            ),
          ],
        ),
        AsyncValue(:final value?) => ContentWidth(child: _TodayList(tasks: value)),
        AsyncValue(:final error?) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: Insets.xxl),
            ErrorState(error: error, onRetry: () => ref.invalidate(myTodayTasksProvider)),
          ],
        ),
        _ => const SkeletonList(),
      },
    );
  }
}

class _TodayList extends StatelessWidget {
  const _TodayList({required this.tasks});

  final List<VisitTask> tasks;

  @override
  Widget build(BuildContext context) {
    final p = DayProgress(tasks);
    // Shops still to visit first, then the ones done.
    final ordered = [...tasks.where((t) => !t.state.visited), ...tasks.where((t) => t.state.visited)];
    final sites = {for (final t in tasks) t.siteName};
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: Insets.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.l),
          child: Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(Insets.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p.visited} of ${plural(p.total, 'shop')} checked in', style: context.text.titleMedium),
                  Text(sites.join(', '), style: context.text.bodySmall),
                  const SizedBox(height: Insets.m),
                  LinearProgressIndicator(value: p.total == 0 ? 0 : p.visited / p.total, borderRadius: BorderRadius.circular(4)),
                ],
              ),
            ),
          ),
        ),
        for (final t in ordered)
          VisitTaskTile(
            task: t,
            showSite: sites.length > 1,
            onTap: () => context.push(t.state.visited ? '/visits/task' : '/visits/check-in', extra: t),
          ),
      ],
    );
  }
}

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(myHistoryProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(myHistoryProvider.future),
      child: switch (tasks) {
        AsyncValue(:final value?) when value.isEmpty => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: Insets.xxl),
            EmptyState(icon: Icons.history_rounded, title: 'No visits in the last 30 days'),
          ],
        ),
        AsyncValue(:final value?) => ContentWidth(child: VisitHistoryList(tasks: value)),
        AsyncValue(:final error?) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: Insets.xxl),
            ErrorState(error: error, onRetry: () => ref.invalidate(myHistoryProvider)),
          ],
        ),
        _ => const SkeletonList(),
      },
    );
  }
}

/// Visits grouped by day, newest first, each day with its tally.
class VisitHistoryList extends StatelessWidget {
  const VisitHistoryList({super.key, required this.tasks, this.showStaff = false});

  final List<VisitTask> tasks;
  final bool showStaff;

  @override
  Widget build(BuildContext context) {
    final byDay = <DateTime, List<VisitTask>>{};
    for (final t in tasks) {
      byDay.putIfAbsent(t.visitDate, () => []).add(t);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: Insets.xxl),
      children: [
        for (final d in days) ...[
          Container(
            color: context.colors.surfaceContainer,
            padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.m),
            child: Row(
              children: [
                Expanded(child: Text(dayLabel(d), style: context.text.titleSmall)),
                Text('${DayProgress(byDay[d]!).visited}/${byDay[d]!.length} visited', style: context.text.labelMedium),
              ],
            ),
          ),
          for (final t in byDay[d]!)
            VisitTaskTile(
              task: t,
              showStaff: showStaff,
              onTap: () => context.push('/visits/task', extra: t),
            ),
        ],
      ],
    );
  }
}
