import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../sites/presentation/site_providers.dart';
import '../domain/visit.dart';
import 'visit_providers.dart';

/// Owner dashboard: how today's planned shop visits are going. Hidden on days
/// with nothing planned.
class VisitsTodayCard extends ConsumerWidget {
  const VisitsTodayCard({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final tasks = ref.watch(companyDayTasksProvider(companyId, DateTime(now.year, now.month, now.day))).value;
    if (tasks == null || tasks.isEmpty) return const SizedBox.shrink();
    final p = DayProgress(tasks);
    final staff = {for (final t in tasks) t.staffId}.length;
    return Padding(
      padding: const EdgeInsets.only(top: Insets.m),
      child: Card.filled(
        child: InkWell(
          onTap: () {
            ref.read(sitesTabControllerProvider.notifier).set(SitesTab.visits);
            ref.read(visitDayControllerProvider.notifier).set(now);
            context.go('/sites');
          },
          child: Padding(
            padding: const EdgeInsets.all(Insets.l),
            child: Row(
              children: [
                const Icon(Icons.where_to_vote_outlined),
                const SizedBox(width: Insets.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Visits today: ${p.visited} of ${p.total}', style: context.text.titleMedium),
                      Text(
                        [
                          plural(staff, 'staff member', 'staff members'),
                          if (p.pending > 0) '${p.pending} to go',
                          if (p.missed > 0) '${p.missed} missed',
                        ].join(' · '),
                        style: context.text.bodySmall,
                      ),
                      const SizedBox(height: Insets.s),
                      LinearProgressIndicator(value: p.visited / p.total, borderRadius: BorderRadius.circular(4)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
