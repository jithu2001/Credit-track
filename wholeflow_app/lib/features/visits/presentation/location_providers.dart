import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/shop_location_repository.dart';
import '../domain/shop_location.dart';

part 'location_providers.g.dart';

/// A shop's pin, or null when it has none.
@riverpod
Future<ShopLocation?> shopLocation(Ref ref, String shopId) => ref.watch(shopLocationRepositoryProvider).location(shopId);

/// Staff suggestions waiting for the owner.
@riverpod
Future<List<LocationSuggestion>> pendingSuggestions(Ref ref) => ref.watch(shopLocationRepositoryProvider).pendingSuggestions();
