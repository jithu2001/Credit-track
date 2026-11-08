import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shop_map.dart';
import '../../../core/widgets/states.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/shop_location.dart';
import 'location_providers.dart';

/// The shop's pin on its Details tab. Owners set or change it; staff only see it.
/// Anyone can get directions to a set pin in their maps app.
class ShopLocationCard extends ConsumerWidget {
  const ShopLocationCard({super.key, required this.shopId, this.shopName});

  final String shopId;
  final String? shopName;

  /// Opens the phone's maps app at the pin: Android's `geo:` lets the user pick
  /// Google Maps or another app; elsewhere, or without one, Google Maps on the web.
  Future<void> _directions(BuildContext context, ShopLocation loc) async {
    final at = '${loc.latitude},${loc.longitude}';
    final label = shopName?.trim();
    final geo = Uri.parse('geo:$at?q=${Uri.encodeComponent(label == null || label.isEmpty ? at : '$at($label)')}');
    final web = Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': at});
    var ok = false;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      ok = await launchUrl(geo, mode: LaunchMode.externalApplication).catchError((_) => false);
    }
    if (!ok) ok = await launchUrl(web, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) showMessage(context, "Couldn't open a maps app.");
  }

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
          if (value != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.l),
              child: FilledButton.tonalIcon(
                key: const Key('shop-directions'),
                onPressed: () => _directions(context, value),
                icon: const Icon(Icons.directions_rounded),
                label: const Text('Directions'),
              ),
            ),
        ],
      ),
    );
  }
}
