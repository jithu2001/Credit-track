import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../staff/presentation/staff_providers.dart';
import 'staff_visits_screen.dart';
import 'visit_providers.dart';

/// Owner: one staff member's planned visits over the last 30 days.
class StaffVisitHistoryScreen extends ConsumerWidget {
  const StaffVisitHistoryScreen({super.key, required this.staffId});

  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(staffMemberProvider(staffId)).value?.displayName ?? 'Staff';
    final tasks = ref.watch(staffHistoryProvider(staffId));
    return Scaffold(
      appBar: AppBar(title: Text('$name · visits')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(staffHistoryProvider(staffId).future),
        child: switch (tasks) {
          AsyncValue(:final value?) when value.isEmpty => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: Insets.xxl),
              EmptyState(icon: Icons.history_rounded, title: 'No planned visits in the last 30 days'),
            ],
          ),
          AsyncValue(:final value?) => ContentWidth(child: VisitHistoryList(tasks: value)),
          AsyncValue(:final error?) => ErrorState(error: error, onRetry: () => ref.invalidate(staffHistoryProvider(staffId))),
          _ => const SkeletonList(),
        },
      ),
    );
  }
}
