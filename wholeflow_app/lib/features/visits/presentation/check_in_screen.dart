import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/errors/app_failure.dart';
import '../../../core/location/location_disclosure.dart';
import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/shop_map.dart';
import '../../../core/widgets/states.dart';
import '../data/visit_repository.dart';
import '../domain/visit.dart';
import 'location_providers.dart';
import 'visit_providers.dart';

/// Staff: check in at a planned shop. The phone reads GPS here only; the
/// server measures the distance to the shop's pin and decides.
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key, required this.task});

  final VisitTask task;

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  final _note = TextEditingController();
  LocationReading? _reading;
  String? _locationError;
  bool _locating = false;
  bool _sending = false;
  String? _rejection;

  /// Developer Options are on (release builds only): check-in stays off, as
  /// they are what make fake-GPS apps selectable.
  bool _devMode = false;
  bool _devDialogShown = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back from Settings: check again, so turning them off unblocks.
    _lifecycle = AppLifecycleListener(onResume: _locate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _note.dispose();
    super.dispose();
  }

  static const _locationDeclined = 'Check-in needs your location. Tap the location button to try again.';

  Future<void> _locate() async {
    // Already reading (e.g. resumed after the permission prompt): only
    // re-check Developer options.
    if (_locating) {
      final dev = await ref.read(locationServiceProvider).developerModeOn();
      if (mounted) setState(() => _devMode = dev);
      return;
    }
    setState(() {
      _locating = true;
      _locationError = null;
      _rejection = null;
    });
    final service = ref.read(locationServiceProvider);
    final dev = await service.developerModeOn();
    if (!mounted) return;
    setState(() => _devMode = dev);
    if (dev && !_devDialogShown) {
      _devDialogShown = true;
      unawaited(_showDevModeDialog());
    }
    try {
      if (!await ensureLocationDisclosure(context, service, LocationPurpose.checkIn)) {
        if (mounted) setState(() => _locationError = _locationDeclined);
        return;
      }
      final r = await service.current();
      if (mounted) setState(() => _reading = r);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _locationError = f.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _showDevModeDialog() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: context.colors.error, size: 32),
      title: const Text('Check-in disabled'),
      content: const Text(
        'Developer options are turned on for this phone. For security, check-in is disabled while '
        'Developer options or USB debugging are on, because they allow fake-location apps.\n\n'
        'Turn them off in Settings, then come back.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            ref.read(locationServiceProvider).openDeveloperSettings();
          },
          child: const Text('Open settings'),
        ),
      ],
    ),
  );

  Future<void> _checkIn() async {
    dismissKeyboard();
    final service = ref.read(locationServiceProvider);
    setState(() {
      _sending = true;
      _rejection = null;
    });
    try {
      if (!await ensureLocationDisclosure(context, service, LocationPurpose.checkIn)) {
        if (mounted) setState(() => _locationError = _locationDeclined);
        return;
      }
      // A fresh fix for the check-in itself, never the one shown earlier.
      final r = await service.current();
      final devMode = await service.developerModeOn();
      if (mounted) setState(() => _reading = r);
      final res = await ref
          .read(visitRepositoryProvider)
          .checkIn(widget.task.taskId, r, developerMode: devMode, note: _note.text.trim().isEmpty ? null : _note.text.trim());
      ref
        ..invalidate(myTodayTasksProvider)
        ..invalidate(myHistoryProvider);
      if (!mounted) return;
      if (!res.accepted) {
        setState(
          () => _rejection = checkInRejection(
            res.reason ?? '',
            distanceM: res.distanceM,
            radiusM: res.radiusM,
            accuracyM: r.accuracyMeters,
          ),
        );
        return;
      }
      showMessage(
        context,
        res.result == 'verified'
            ? 'Checked in at ${widget.task.shopName}'
            : 'Checked in. Your owner will confirm this shop\'s location.',
      );
      context.pop();
    } on AppFailure catch (f) {
      if (mounted) setState(() => _rejection = f.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final pin = ref.watch(shopLocationProvider(t.shopId));
    final loc = pin.value;
    final r = _reading;
    final distance = loc != null && r != null
        ? const ll.Distance().as(ll.LengthUnit.Meter, ll.LatLng(loc.latitude, loc.longitude), ll.LatLng(r.latitude, r.longitude))
        : null;
    final inRange = distance != null && distance <= loc!.radiusM;
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text(t.shopName, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(Insets.l),
          children: [
            Text(t.siteName, style: muted),
            const SizedBox(height: Insets.m),
            SizedBox(
              height: 260,
              child: ShopMap(
                shopLat: loc?.latitude,
                shopLng: loc?.longitude,
                radiusMeters: loc?.radiusM.toDouble(),
                deviceLat: r?.latitude,
                deviceLng: r?.longitude,
              ),
            ),
            const SizedBox(height: Insets.l),
            if (pin.hasValue && loc == null)
              const _Info(
                icon: Icons.add_location_alt_outlined,
                text: 'This shop has no location yet. Check in while standing at the shop and your owner will confirm it.',
              ),
            if (_locating) const _Info(icon: Icons.gps_not_fixed_rounded, text: 'Finding your location…'),
            if (_locationError != null) _Info(icon: Icons.gps_off_rounded, text: _locationError!, error: true),
            if (r != null && !_locating) ...[
              if (distance != null)
                Text(
                  '${distance.round()} m from the shop',
                  style: context.text.headlineSmall?.copyWith(
                    color: inRange ? context.semantic.credit : context.semantic.owed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                [
                  if (loc != null) 'Allowed ${loc.radiusM} m',
                  'GPS ±${r.accuracyMeters.round()} m${r.accuracyMeters > 50 ? ' (needs 50 m or better)' : ''}',
                ].join(' · '),
                style: muted,
              ),
              if (r.isMocked)
                const _Info(
                  icon: Icons.warning_amber_rounded,
                  text: 'A fake location app is on. Turn it off to check in.',
                  error: true,
                ),
              if (distance != null && !inRange)
                const _Info(icon: Icons.directions_walk_rounded, text: 'Move closer to the shop to check in.'),
              if (loc != null && r.accuracyMeters > loc.radiusM)
                _Info(
                  icon: Icons.gps_not_fixed_rounded,
                  text:
                      'Your GPS (±${r.accuracyMeters.round()} m) is rougher than this shop\'s ${loc.radiusM} m limit. '
                      'Step outside or near the door, wait a few seconds, then refresh.',
                ),
            ],
            const SizedBox(height: Insets.l),
            TextField(
              controller: _note,
              maxLength: 500,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. Owner not in, come back Friday'),
            ),
            if (_devMode)
              const _Info(
                icon: Icons.developer_mode_rounded,
                text: 'Check-in is off while Developer options are on. Turn them off in Settings and come back.',
                error: true,
              ),
            if (_rejection != null) _Info(icon: Icons.block_rounded, text: 'Check-in refused: $_rejection', error: true),
            const SizedBox(height: Insets.m),
            Row(
              children: [
                IconButton.outlined(
                  tooltip: 'Refresh location',
                  onPressed: _locating || _sending ? null : _locate,
                  icon: const Icon(Icons.my_location_rounded),
                ),
                const SizedBox(width: Insets.m),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('check-in'),
                    onPressed: _sending || _locating || _devMode ? null : _checkIn,
                    icon: _sending
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.where_to_vote_rounded),
                    label: const Text('Check in'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.s),
            Text('Your location is read only on this screen. The time and distance are recorded by the server.', style: muted),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text, this.error = false});

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? context.colors.error : context.colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: Insets.s),
          Expanded(
            child: Text(text, style: context.text.bodyMedium?.copyWith(color: error ? color : null)),
          ),
        ],
      ),
    );
  }
}
