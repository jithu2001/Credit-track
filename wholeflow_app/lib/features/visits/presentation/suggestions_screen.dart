import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shop_map.dart';
import '../../../core/widgets/states.dart';
import '../data/shop_location_repository.dart';
import '../domain/shop_location.dart';
import 'location_providers.dart';

/// Owner: staff checked in at shops that had no pin. Approve to pin the shop
/// where they stood (their waiting visits become verified), or reject.
class SuggestionsScreen extends ConsumerWidget {
  const SuggestionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pendingSuggestionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Locations to review')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pendingSuggestionsProvider.future),
        child: switch (list) {
          AsyncValue(:final value?) when value.isEmpty => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: Insets.xxl),
              EmptyState(
                icon: Icons.where_to_vote_outlined,
                title: 'Nothing to review',
                message: 'When staff check in at a shop with no location, it shows up here.',
              ),
            ],
          ),
          AsyncValue(:final value?) => ContentWidth(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Insets.l),
              itemCount: value.length,
              separatorBuilder: (_, _) => const SizedBox(height: Insets.l),
              itemBuilder: (context, i) => _SuggestionCard(s: value[i]),
            ),
          ),
          AsyncValue(:final error?) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: Insets.xxl),
              ErrorState(error: error, onRetry: () => ref.invalidate(pendingSuggestionsProvider)),
            ],
          ),
          _ => const SkeletonList(),
        },
      ),
    );
  }
}

class _SuggestionCard extends ConsumerStatefulWidget {
  const _SuggestionCard({required this.s});

  final LocationSuggestion s;

  @override
  ConsumerState<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends ConsumerState<_SuggestionCard> {
  bool _busy = false;

  Future<void> _review(bool approve) async {
    setState(() => _busy = true);
    try {
      await ref.read(shopLocationRepositoryProvider).review(widget.s.id, approve: approve);
      ref
        ..invalidate(pendingSuggestionsProvider)
        ..invalidate(shopLocationProvider(widget.s.shopId));
      if (mounted) showMessage(context, approve ? '${widget.s.shopName} pinned' : 'Suggestion rejected');
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(s.shopName, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                if (s.staffName != null) s.staffName!,
                formatDateTime(s.createdAt),
                if (s.accuracyM != null) 'GPS ±${s.accuracyM!.round()} m',
              ].join(' · '),
              style: muted,
            ),
            trailing: IconButton(
              tooltip: 'Open shop',
              icon: const Icon(Icons.storefront_outlined),
              onPressed: () => context.push('/shop/${s.shopId}'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.l),
            child: SizedBox(
              height: 180,
              child: ShopMap(
                shopLat: s.latitude,
                shopLng: s.longitude,
                radiusMeters: ShopLocation.defaultRadius.toDouble(),
                interactive: false,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Insets.l),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: _busy ? null : () => _review(false), child: const Text('Reject')),
                ),
                const SizedBox(width: Insets.m),
                Expanded(
                  child: FilledButton(onPressed: _busy ? null : () => _review(true), child: const Text('Approve pin')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
