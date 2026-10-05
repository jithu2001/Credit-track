import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shop_map.dart';
import '../../../core/widgets/states.dart';
import '../../auth/presentation/session_controller.dart';
import 'location_providers.dart';

/// The shop's pin on its Details tab. Owners set or change it; staff only see it.
class ShopLocationCard extends ConsumerWidget {
  const ShopLocationCard({super.key, required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(currentUserProvider)?.isOwner ?? false;
    final loc = ref.watch(shopLocationProvider(shopId));
    final value = loc.value;
    if (!isOwner && value == null) return const SizedBox.shrink();
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(value == null ? Icons.location_off_outlined : Icons.location_on_outlined),
            title: const Text('Shop location'),
            subtitle: Text(switch (loc) {
              AsyncValue(hasValue: true) when value == null => 'Not set. Staff check-ins wait for your approval.',
              AsyncValue(hasValue: true) =>
                'Check-in within ${value!.radiusM} m${value.fromSuggestion ? ' · from a staff visit' : ''}',
              AsyncValue(hasError: true) => "Couldn't load the location",
              _ => 'Loading…',
            }),
            trailing: isOwner && loc.hasValue
                ? TextButton(
                    key: const Key('edit-location'),
                    onPressed: () => context.push('/shop/$shopId/location'),
                    child: Text(value == null ? 'Set' : 'Change'),
                  )
                : null,
          ),
          if (loc case AsyncValue(:final error?))
            ErrorTile(error: error, onRetry: () => ref.invalidate(shopLocationProvider(shopId))),
          if (value != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.l),
              child: SizedBox(
                height: 180,
                child: ShopMap(
                  shopLat: value.latitude,
                  shopLng: value.longitude,
                  radiusMeters: value.radiusM.toDouble(),
                  interactive: false,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
