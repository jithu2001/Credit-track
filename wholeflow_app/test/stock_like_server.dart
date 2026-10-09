import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/features/inventory/domain/stock_item.dart';

/// Test data only: a stock item with the status, minimum and alert fields
/// filled in as the app API does (internal/appapi/stock.go).
StockItem stockItem({
  required String id,
  String? name,
  double qty = 0,
  double? min,
  double reorder = 0,
  String? group,
  String? unit,
  Money? value,
  Money? rate,
  DateTime? syncedAt,
  DateTime? lastPurchaseDate,
  Money? lastPurchaseRate,
  String? lastSupplier,
  List<String> aliases = const [],
}) {
  final effective = (min ?? 0) > 0 ? min! : (reorder > 0 ? reorder : 0.0);
  final below = effective > 0 && qty <= effective;
  return StockItem(
    id: id,
    name: name ?? id,
    aliases: aliases,
    group: group,
    unit: unit,
    closingQty: qty,
    reorderLevel: reorder,
    minQty: (min ?? 0) > 0 ? min : null,
    effectiveMin: effective,
    atOrBelowMinimum: below,
    shortfall: below ? effective - qty : 0,
    status: qty < 0
        ? StockStatus.negative
        : qty == 0
        ? StockStatus.zero
        : below
        ? StockStatus.low
        : StockStatus.inStock,
    closingValue: value,
    closingRate: rate,
    syncedAt: syncedAt,
    lastPurchaseDate: lastPurchaseDate,
    lastPurchaseRate: lastPurchaseRate,
    lastSupplier: lastSupplier,
  );
}

/// Test data only: [items] as `GET /stock` answers (summary and alert order).
StockList stockListOf(List<StockItem> items) {
  final alerts = [...items.where((i) => i.atOrBelowMinimum)]
    ..sort((a, b) {
      final c = (b.shortfall / b.effectiveMin).compareTo(a.shortfall / a.effectiveMin);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  DateTime? synced;
  for (final i in items) {
    if (i.syncedAt != null && (synced == null || i.syncedAt!.isAfter(synced))) synced = i.syncedAt;
  }
  return StockList(
    items: [...items]..sort((a, b) => a.name.compareTo(b.name)),
    summary: StockSummary(
      items: items.length,
      value: items.fold(Money.zero, (t, i) => t + (i.closingValue ?? Money.zero)),
      byStatus: {for (final s in StockStatus.values) s: items.where((i) => i.status == s).length},
      syncedAt: synced,
    ),
    alerts: alerts,
  );
}

/// Test data only: [i] after the owner sets [min] (null or 0 removes it).
StockItem withMinimum(StockItem i, double? min) => stockItem(
  id: i.id,
  name: i.name,
  qty: i.closingQty,
  min: min,
  reorder: i.reorderLevel,
  group: i.group,
  unit: i.unit,
  value: i.closingValue,
  syncedAt: i.syncedAt,
);
