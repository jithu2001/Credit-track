import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/shop_location.dart';

/// Shop pins and staff suggestions, from the app API. Pins change only
/// through the owner-only database functions; staff read the pins of their shops.
class ShopLocationRepository {
  ShopLocationRepository(this._api);

  final ApiClient _api;

  Future<ShopLocation?> location(String shopId) async {
    try {
      final row = (await _api.get('shops/$shopId/location'))['location'];
      return row is Map<String, dynamic> ? ShopLocation.fromJson(row) : null;
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> setLocation(String shopId, double lat, double lng, int radiusM) async {
    try {
      await _api.put('shops/$shopId/location', {'latitude': lat, 'longitude': lng, 'radius_m': radiusM});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> clearLocation(String shopId) async {
    try {
      await _api.delete('shops/$shopId/location');
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Suggestions waiting for the owner, oldest first.
  Future<List<LocationSuggestion>> pendingSuggestions() async {
    try {
      final body = await _api.get('location-suggestions');
      return [for (final r in (body['suggestions'] as List).cast<Map<String, dynamic>>()) LocationSuggestion.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> review(String suggestionId, {required bool approve, int radiusM = ShopLocation.defaultRadius}) async {
    try {
      await _api.post('location-suggestions/$suggestionId/review', {'approve': approve, 'radius_m': radiusM});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

final shopLocationRepositoryProvider = Provider<ShopLocationRepository>(
  (ref) => ShopLocationRepository(ref.watch(apiClientProvider)),
);
