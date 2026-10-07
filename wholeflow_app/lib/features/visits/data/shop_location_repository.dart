import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../domain/shop_location.dart';

/// Shop pins and staff suggestions. Pins are written only through the
/// owner-only functions `set_shop_location`, `clear_shop_location` and
/// `review_location_suggestion`; RLS lets staff read the pins of their shops.
class ShopLocationRepository {
  ShopLocationRepository(this._client);

  final SupabaseClient _client;

  Future<ShopLocation?> location(String shopId) async {
    try {
      final row = await _client.from('shop_locations').select(ShopLocation.columns).eq('shop_id', shopId).maybeSingle();
      return row == null ? null : ShopLocation.fromJson(row);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> setLocation(String shopId, double lat, double lng, int radiusM) async {
    try {
      await _client.rpc('set_shop_location', params: {'p_shop_id': shopId, 'p_lat': lat, 'p_lng': lng, 'p_radius_m': radiusM});
    } on PostgrestException catch (e) {
      // A radius the database's range check refuses (e.g. 5–10 m before migration 0006).
      if (e.code == '23514') {
        throw AppFailure(
          FailureKind.invalidInput,
          'The server does not accept a $radiusM m radius yet. Choose 20 m or more, or update the server and try again.',
        );
      }
      throw AppFailure.from(e);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> clearLocation(String shopId) async {
    try {
      await _client.rpc('clear_shop_location', params: {'p_shop_id': shopId});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Suggestions waiting for the owner, oldest first.
  Future<List<LocationSuggestion>> pendingSuggestions() async {
    try {
      final rows = await _client
          .from('shop_location_suggestions')
          .select(LocationSuggestion.columns)
          .eq('status', 'pending')
          .order('created_at');
      return rows.map(LocationSuggestion.fromJson).toList();
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> review(String suggestionId, {required bool approve, int radiusM = ShopLocation.defaultRadius}) async {
    try {
      await _client.rpc(
        'review_location_suggestion',
        params: {'p_id': suggestionId, 'p_approve': approve, 'p_radius_m': radiusM},
      );
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

final shopLocationRepositoryProvider = Provider<ShopLocationRepository>(
  (ref) => ShopLocationRepository(ref.watch(supabaseProvider)),
);
