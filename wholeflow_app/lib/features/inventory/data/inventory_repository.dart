import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/stock_item.dart';

/// Stock from the WholeFlow app API. Owners get cost and the last purchase;
/// staff get quantities only, for companies they are assigned to. Status,
/// minimum and the stock alert are worked out on the server.
class InventoryRepository {
  InventoryRepository(this._api);

  final ApiClient _api;

  /// Every active stock item of a company (by name), its totals and the alert.
  Future<StockList> items(String companyId) async {
    try {
      return StockList.fromJson(await _api.get('stock', {'company': companyId}));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Sets [min] as the minimum stock of every item in [itemIds]; null or 0
  /// removes it. Owner only (the server refuses anyone else).
  Future<void> setMinimum(String companyId, Iterable<String> itemIds, double? min) async {
    try {
      await _api.put('stock/minimum', {'company': companyId, 'items': itemIds.toSet().toList(), 'min': min});
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<StockItem> item(String itemId) async {
    try {
      return StockItem.fromJson(await _api.get('stock/$itemId'));
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// The latest purchase bills containing [itemId] (owner only).
  Future<List<ItemPurchase>> purchasesOf(String itemId) async {
    try {
      final body = await _api.get('stock/$itemId/purchases');
      return [for (final r in (body['purchases'] as List).cast<Map<String, dynamic>>()) ItemPurchase.fromJson(r)];
    } catch (e) {
      throw AppFailure.from(e);
    }
  }
}

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) => InventoryRepository(ref.watch(apiClientProvider)));
