import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/session_controller.dart';
import '../data/inventory_repository.dart';
import '../domain/stock_item.dart';

/// Only owners load purchase prices and stock values.
bool _withCosts(Ref ref) => ref.watch(currentUserProvider)?.isOwner ?? false;

/// Every stock item of a company; searched and filtered on the phone.
final stockItemsProvider = FutureProvider.autoDispose.family<List<StockItem>, String>(
  (ref, companyId) => ref.watch(inventoryRepositoryProvider).items(companyId, withCosts: _withCosts(ref)),
);

final stockItemProvider = FutureProvider.autoDispose.family<StockItem, String>(
  (ref, itemId) => ref.watch(inventoryRepositoryProvider).item(itemId, withCosts: _withCosts(ref)),
);

/// Recent purchase bills of an item (owner only).
final itemPurchasesProvider = FutureProvider.autoDispose.family<List<ItemPurchase>, String>(
  (ref, itemId) => ref.watch(inventoryRepositoryProvider).purchasesOf(itemId),
);

/// The inventory list's status filter. Kept here (not in the list's own state)
/// so the dashboard's stock alert can open the list already filtered.
final inventoryStatusFilterProvider = NotifierProvider<InventoryStatusFilter, StockStatus?>(InventoryStatusFilter.new);

class InventoryStatusFilter extends Notifier<StockStatus?> {
  @override
  StockStatus? build() => null;

  void set(StockStatus? status) => state = status;
}

/// The inventory list's "Below minimum" filter, also set by the dashboard's
/// stock alert.
final inventoryBelowMinimumProvider = NotifierProvider<InventoryBelowMinimum, bool>(InventoryBelowMinimum.new);

class InventoryBelowMinimum extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool on) => state = on;
}

/// Sets (or with null/0 removes) the minimum stock of [itemIds] and reloads
/// the lists that show it.
Future<void> setStockMinimum(WidgetRef ref, String companyId, Iterable<String> itemIds, double? min) async {
  await ref.read(inventoryRepositoryProvider).setMinimum(companyId, itemIds, min);
  ref.invalidate(stockItemsProvider(companyId));
  for (final id in itemIds) {
    ref.invalidate(stockItemProvider(id));
  }
}
