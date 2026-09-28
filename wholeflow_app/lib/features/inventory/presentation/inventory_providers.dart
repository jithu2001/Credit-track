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
