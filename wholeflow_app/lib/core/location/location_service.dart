import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../errors/app_failure.dart';

/// One fresh GPS fix.
class LocationReading {
  const LocationReading({required this.latitude, required this.longitude, required this.accuracyMeters, required this.isMocked});

  final double latitude;
  final double longitude;
  final double accuracyMeters;

  /// Android's mock-provider flag for this fix: a signal, not proof.
  final bool isMocked;
}

/// The only place the app reads the device location. Location is read only
/// while a pin or check-in screen asks for it; there is no background tracking.
class LocationService {
  const LocationService();

  static const _integrity = MethodChannel('wholeflow/device_integrity');

  /// A fresh high-accuracy fix, never a cached one; throws [AppFailure] with
  /// a message the screen can show.
  Future<LocationReading> current({Duration timeout = const Duration(seconds: 20)}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AppFailure(FailureKind.invalidInput, 'Turn on Location in your phone settings, then try again.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw const AppFailure(FailureKind.forbidden, 'WholeFlow needs your location for this. Allow it and try again.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const AppFailure(
        FailureKind.forbidden,
        'Location is blocked for WholeFlow. Allow it in Settings → Apps → WholeFlow → Permissions.',
      );
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.best, timeLimit: timeout),
      );
      return LocationReading(latitude: p.latitude, longitude: p.longitude, accuracyMeters: p.accuracy, isMocked: p.isMocked);
    } catch (_) {
      throw const AppFailure(FailureKind.network, "Couldn't get your location. Go outside or near a window and try again.");
    }
  }

  /// Whether Developer Options are on. Only checked in release builds, so a
  /// phone used for development (USB debugging needs them) is not blocked.
  Future<bool> developerModeOn() async {
    if (!kReleaseMode) return false;
    try {
      return await _integrity.invokeMethod<bool>('isDeveloperModeEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> openSettings() => Geolocator.openAppSettings();

  /// Android's Developer options page, so staff can turn them off.
  Future<void> openDeveloperSettings() async {
    try {
      await _integrity.invokeMethod<void>('openDeveloperSettings');
    } on PlatformException {
      await Geolocator.openAppSettings();
    } on MissingPluginException {
      // Not Android: nothing to open.
    }
  }
}

final locationServiceProvider = Provider<LocationService>((ref) => const LocationService());
