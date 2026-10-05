import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/errors/app_failure.dart';
import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shop_map.dart';
import '../../../core/widgets/states.dart';
import '../../shop_detail/presentation/shop_detail_providers.dart';
import '../data/shop_location_repository.dart';
import '../domain/shop_location.dart';
import 'location_providers.dart';

/// Owner: put a shop's pin where the shop is and choose how close staff must
/// be to check in.
class LocationEditorScreen extends ConsumerWidget {
  const LocationEditorScreen({super.key, required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(shopLocationProvider(shopId));
    final name = ref.watch(shopDetailProvider(shopId)).value?.name ?? 'Shop location';
    return switch (loc) {
      AsyncValue(hasValue: true, :final value) => _Editor(shopId: shopId, shopName: name, initial: value),
      AsyncValue(:final error?) => Scaffold(
        appBar: AppBar(title: Text(name)),
        body: ErrorState(error: error, onRetry: () => ref.invalidate(shopLocationProvider(shopId))),
      ),
      _ => Scaffold(
        appBar: AppBar(title: Text(name)),
        body: const SkeletonList(),
      ),
    };
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.shopId, required this.shopName, required this.initial});

  final String shopId;
  final String shopName;
  final ShopLocation? initial;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  static const _radii = [5, 10, 20, 50, 100, 200, 500, 1000];

  late ll.LatLng? _point = widget.initial == null ? null : ll.LatLng(widget.initial!.latitude, widget.initial!.longitude);
  late int _radius = widget.initial?.radiusM ?? ShopLocation.defaultRadius;
  ll.LatLng? _device;
  double? _accuracy;
  bool _locating = false;
  bool _saving = false;

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final r = await ref.read(locationServiceProvider).current();
      if (!mounted) return;
      if (r.isMocked) {
        showMessage(context, 'This location looks fake (mock location is on). Turn it off and try again.');
        return;
      }
      setState(() {
        _device = ll.LatLng(r.latitude, r.longitude);
        _accuracy = r.accuracyMeters;
        _point = _device;
      });
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final p = _point;
    if (p == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(shopLocationRepositoryProvider).setLocation(widget.shopId, p.latitude, p.longitude, _radius);
      ref.invalidate(shopLocationProvider(widget.shopId));
      if (!mounted) return;
      showMessage(context, 'Location saved');
      context.pop();
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this location?'),
        content: const Text(
          'Staff visiting this shop will suggest a location again, and their check-ins wait for you until you approve one.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(shopLocationRepositoryProvider).clearLocation(widget.shopId);
      ref.invalidate(shopLocationProvider(widget.shopId));
      if (mounted) context.pop();
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.shopName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.initial != null)
            IconButton(tooltip: 'Remove location', icon: const Icon(Icons.wrong_location_outlined), onPressed: _remove),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, 0),
                child: PinPicker(
                  point: _point,
                  radiusMeters: _radius.toDouble(),
                  device: _device,
                  onChanged: (p) => setState(() => _point = p),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, Insets.m, Insets.l, 0),
              child: Text(
                _point == null
                    ? 'Tap the map where the shop is, or stand at the shop and use your location.'
                    : 'Tap the map to move the pin. Staff must be within $_radius m of it to check in.',
                style: muted,
              ),
            ),
            if (_accuracy != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Insets.l, Insets.xs, Insets.l, 0),
                child: Text('Your GPS accuracy: ${_accuracy!.round()} m', style: muted),
              ),
            if (_radius < ShopLocation.preciseRadius)
              Padding(
                padding: const EdgeInsets.fromLTRB(Insets.l, Insets.xs, Insets.l, 0),
                child: Text(
                  'Small radius: phone GPS is often off by 10–20 m, so staff may be refused even inside the shop. '
                  'Use it for small shops where staff can wait for a good GPS fix.',
                  key: const Key('small-radius-warning'),
                  style: context.text.bodySmall?.copyWith(color: context.semantic.warning),
                ),
              ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.s),
                children: [
                  for (final r in _radii) ...[
                    ChoiceChip(
                      label: Text(r >= 1000 ? '${r ~/ 1000} km' : '$r m'),
                      selected: _radius == r,
                      onSelected: (_) => setState(() => _radius = r),
                    ),
                    const SizedBox(width: Insets.s),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, 0, Insets.l, Insets.m),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('use-my-location'),
                      onPressed: _locating ? null : _useMyLocation,
                      icon: _locating
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location_rounded),
                      label: const Text('My location'),
                    ),
                  ),
                  const SizedBox(width: Insets.m),
                  Expanded(
                    child: FilledButton(
                      key: const Key('save-location'),
                      onPressed: _point == null || _saving ? null : _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
