import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/visit.dart';

/// A small coloured label for a visit's state.
class VisitStateChip extends StatelessWidget {
  const VisitStateChip(this.state, {super.key});

  final VisitState state;

  @override
  Widget build(BuildContext context) {
    final s = context.semantic;
    final cs = context.colors;
    final (bg, fg, icon) = switch (state) {
      VisitState.verified => (s.creditContainer, s.onCreditContainer, Icons.verified_rounded),
      VisitState.locationPending => (cs.secondaryContainer, cs.onSecondaryContainer, Icons.pending_outlined),
      VisitState.unverified => (s.warningContainer, s.onWarningContainer, Icons.gpp_maybe_outlined),
      VisitState.pending => (cs.surfaceContainerHighest, cs.onSurfaceVariant, Icons.schedule_rounded),
      VisitState.missed => (s.owedContainer, s.onOwedContainer, Icons.event_busy_outlined),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.s, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(state.label, style: context.text.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// One task as a list row: shop, site and time, with its state.
class VisitTaskTile extends StatelessWidget {
  const VisitTaskTile({super.key, required this.task, this.onTap, this.showSite = true, this.showStaff = false});

  final VisitTask task;
  final VoidCallback? onTap;
  final bool showSite;
  final bool showStaff;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final details = [
      if (showStaff) t.staffName,
      if (showSite) t.siteName,
      if (t.checkedInAt != null) DateFormat('h:mm a').format(t.checkedInAt!),
      if (t.distanceM != null) '${t.distanceM!.round()} m',
    ].where((s) => s.isNotEmpty).join(' · ');
    return ListTile(
      onTap: onTap,
      title: Text(t.shopName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.isNotEmpty) Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (t.note != null && t.note!.isNotEmpty)
            Text(
              '“${t.note}”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
        ],
      ),
      trailing: VisitStateChip(t.state),
    );
  }
}

/// "Today", "Yesterday", "Tomorrow" or "Mon, 7 Oct".
String dayLabel(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
  return switch (diff) {
    0 => 'Today',
    -1 => 'Yesterday',
    1 => 'Tomorrow',
    _ => DateFormat('EEE, d MMM').format(d),
  };
}
