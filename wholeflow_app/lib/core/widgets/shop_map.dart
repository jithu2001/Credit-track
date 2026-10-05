import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

/// The only widgets that know the map is flutter_map with OpenStreetMap tiles
/// (no API key); switching providers only touches this file.
TileLayer _tiles() =>
    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.wholeflow.wholeflow_app');

CircleLayer _radius(BuildContext context, ll.LatLng point, double meters) {
  final c = Theme.of(context).colorScheme.primary;
  return CircleLayer(
    circles: [
      CircleMarker(
        point: point,
        radius: meters,
        useRadiusInMeter: true,
        color: c.withValues(alpha: 0.15),
        borderColor: c,
        borderStrokeWidth: 2,
      ),
    ],
  );
}

Marker _pin(BuildContext context, ll.LatLng point) => Marker(
  point: point,
  width: 40,
  height: 40,
  alignment: Alignment.topCenter,
  child: Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary, size: 40),
);

Marker _device(BuildContext context, ll.LatLng point) {
  final cs = Theme.of(context).colorScheme;
  return Marker(
    point: point,
    width: 22,
    height: 22,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: cs.tertiary,
        shape: BoxShape.circle,
        border: Border.all(color: cs.surface, width: 3),
      ),
    ),
  );
}

/// Read-only: a shop's pin and radius, and where a phone was (if known).
class ShopMap extends StatelessWidget {
  const ShopMap({
    super.key,
    this.shopLat,
    this.shopLng,
    this.radiusMeters,
    this.deviceLat,
    this.deviceLng,
    this.interactive = true,
  });

  final double? shopLat;
  final double? shopLng;
  final double? radiusMeters;
  final double? deviceLat;
  final double? deviceLng;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final shop = shopLat != null && shopLng != null ? ll.LatLng(shopLat!, shopLng!) : null;
    final device = deviceLat != null && deviceLng != null ? ll.LatLng(deviceLat!, deviceLng!) : null;
    final center = shop ?? device ?? const ll.LatLng(9.9, 76.7);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      // The pin and the GPS fix usually arrive after the first frame: a new
      // key re-centres the map on them.
      child: FlutterMap(
        key: ValueKey((shop, device == null)),
        options: MapOptions(
          initialCenter: center,
          initialZoom: 17,
          interactionOptions: InteractionOptions(flags: interactive ? InteractiveFlag.all : InteractiveFlag.none),
        ),
        children: [
          _tiles(),
          if (shop != null && radiusMeters != null) _radius(context, shop, radiusMeters!),
          MarkerLayer(markers: [if (shop != null) _pin(context, shop), if (device != null) _device(context, device)]),
        ],
      ),
    );
  }
}

/// Editable: tap the map to move the pin; the radius circle follows.
class PinPicker extends StatefulWidget {
  const PinPicker({super.key, required this.point, required this.radiusMeters, required this.onChanged, this.device});

  /// Where the pin is; null shows the region and waits for a tap.
  final ll.LatLng? point;
  final double radiusMeters;
  final ValueChanged<ll.LatLng> onChanged;

  /// The phone's own position, drawn as a dot when known.
  final ll.LatLng? device;

  @override
  State<PinPicker> createState() => _PinPickerState();
}

class _PinPickerState extends State<PinPicker> {
  final _map = MapController();

  @override
  void didUpdateWidget(covariant PinPicker old) {
    super.didUpdateWidget(old);
    // "Use my location" moves the pin from outside: follow it.
    final p = widget.point;
    if (p != null && p != old.point && p != _lastTapped) _map.move(p, 18);
  }

  ll.LatLng? _lastTapped;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.point;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: p ?? widget.device ?? const ll.LatLng(9.9, 76.7),
          initialZoom: p != null || widget.device != null ? 17 : 9,
          onTap: (_, point) {
            _lastTapped = point;
            widget.onChanged(point);
          },
        ),
        children: [
          _tiles(),
          if (p != null) _radius(context, p, widget.radiusMeters),
          MarkerLayer(markers: [if (widget.device != null) _device(context, widget.device!), if (p != null) _pin(context, p)]),
        ],
      ),
    );
  }
}
