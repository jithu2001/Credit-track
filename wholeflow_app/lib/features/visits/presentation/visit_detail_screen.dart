import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shop_map.dart';
import '../../../core/widgets/states.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/visit.dart';
import 'location_providers.dart';
import 'visit_providers.dart';
import 'visit_widgets.dart';

/// One planned visit: where the phone was against the shop's pin, when, and
/// (owners) any refused attempts.
class VisitDetailScreen extends ConsumerWidget {
  const VisitDetailScreen({super.key, required this.task});

  final VisitTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(currentUserProvider)?.isOwner ?? false;
    final visit = task.visitId == null ? null : ref.watch(shopVisitProvider(task.visitId!));
    final pin = ref.watch(shopLocationProvider(task.shopId)).value;
    final attempts = isOwner ? ref.watch(failedAttemptsProvider(task.taskId)).value ?? const [] : const <FailedAttempt>[];
    final v = visit?.value;
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: Text(task.shopName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Open shop',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () => context.push('/shop/${task.shopId}'),
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(Insets.l),
          children: [
            Row(
              children: [
                VisitStateChip(task.state),
                const SizedBox(width: Insets.s),
                Expanded(
                  child: Text(
                    '${dayLabel(task.visitDate)} · ${task.siteName}${isOwner ? ' · ${task.staffName}' : ''}',
                    style: muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.l),
            if (v != null || pin != null)
              SizedBox(
                height: 260,
                child: ShopMap(
                  shopLat: v?.shopLat ?? pin?.latitude,
                  shopLng: v?.shopLng ?? pin?.longitude,
                  radiusMeters: (v?.radiusM ?? pin?.radiusM)?.toDouble(),
                  deviceLat: v?.deviceLat,
                  deviceLng: v?.deviceLng,
                ),
              ),
            if (v != null || pin != null)
              Padding(
                padding: const EdgeInsets.only(top: Insets.s),
                child: Text('Pin and radius: the shop. Dot: where the phone was at check-in.', style: muted),
              ),
            const SizedBox(height: Insets.l),
            if (visit case AsyncValue(:final error?))
              ErrorTile(error: error, onRetry: () => ref.invalidate(shopVisitProvider(task.visitId!))),
            if (v != null)
              Card.outlined(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.schedule_rounded),
                      title: Text(DateFormat('d MMM yyyy, h:mm a').format(v.checkedInAt)),
                      subtitle: const Text('Checked in (server time)'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.straighten_rounded),
                      title: Text(
                        v.distanceM == null
                            ? 'No pin yet: waiting for the owner'
                            : '${v.distanceM!.round()} m from the shop (allowed ${v.radiusM} m)',
                      ),
                      subtitle: Text('GPS accuracy ±${v.accuracyM.round()} m'),
                    ),
                    if (v.note != null && v.note!.isNotEmpty)
                      ListTile(leading: const Icon(Icons.notes_rounded), title: Text(v.note!), subtitle: const Text('Note')),
                  ],
                ),
              )
            else if (visit == null)
              Card.outlined(
                child: ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(task.state == VisitState.missed ? 'No check-in on this day' : 'Not checked in yet'),
                ),
              ),
            if (attempts.isNotEmpty) ...[
              const SizedBox(height: Insets.l),
              Text('Refused attempts', style: context.text.titleSmall),
              for (final a in attempts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.block_rounded, color: context.colors.error),
                  title: Text(a.label),
                  subtitle: Text(DateFormat('h:mm a').format(a.at)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
