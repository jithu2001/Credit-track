import '../../../core/format.dart';
import '../../../core/money/money.dart';

/// `stock_items.stock_status`, computed by the sync service from Tally.
enum StockStatus {
  inStock('in_stock', 'In stock'),
  low('low', 'Low stock'),
  zero('zero', 'Out of stock'),
  negative('negative', 'Negative stock');

  const StockStatus(this.code, this.label);

  final String code;
  final String label;

  static StockStatus parse(Object? code) => values.firstWhere((s) => s.code == code, orElse: () => StockStatus.zero);
}

/// A Tally stock item. Staff rows are loaded without the cost fields (valuation
/// rate, stock value, last purchase), so those are null for staff.
class StockItem {
  const StockItem({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.group,
    this.unit,
    this.closingQty = 0,
    this.reorderLevel = 0,
    this.status = StockStatus.zero,
    this.syncedAt,
    this.closingRate,
    this.closingValue,
    this.lastPurchaseDate,
    this.lastPurchaseRate,
    this.lastSupplier,
  });

  /// From `v_stock_items` (owner): includes cost and the latest purchase.
  static const ownerColumns =
      'stock_item_id,name,aliases,stock_group,unit,closing_qty,closing_rate,closing_value,reorder_level,stock_status,'
      'synced_at,last_purchase_date,last_purchase_rate,last_supplier';

  /// From `stock_items` (staff): quantities only, no purchase prices.
  static const staffColumns = 'id,name,aliases,stock_group,unit,closing_qty,reorder_level,stock_status,synced_at';

  factory StockItem.fromJson(Map<String, dynamic> json) {
    Money? money(String key) => json[key] == null ? null : Money.parse(json[key]);
    return StockItem(
      id: (json['stock_item_id'] ?? json['id']) as String,
      name: (json['name'] as String?) ?? '',
      aliases: parseStrings(json['aliases']),
      group: json['stock_group'] as String?,
      unit: json['unit'] as String?,
      closingQty: parseQty(json['closing_qty']),
      reorderLevel: parseQty(json['reorder_level']),
      status: StockStatus.parse(json['stock_status']),
      syncedAt: json['synced_at'] == null ? null : DateTime.tryParse(json['synced_at'] as String),
      closingRate: money('closing_rate'),
      closingValue: money('closing_value'),
      lastPurchaseDate: parseDate(json['last_purchase_date']),
      lastPurchaseRate: money('last_purchase_rate'),
      lastSupplier: json['last_supplier'] as String?,
    );
  }

  final String id;
  final String name;

  /// Part numbers and alternate names from Tally.
  final List<String> aliases;
  final String? group;
  final String? unit;
  final double closingQty;
  final double reorderLevel;
  final StockStatus status;
  final DateTime? syncedAt;

  // Owner only.
  final Money? closingRate;
  final Money? closingValue;
  final DateTime? lastPurchaseDate;
  final Money? lastPurchaseRate;
  final String? lastSupplier;

  /// Case-insensitive match on name, part numbers and group.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        aliases.any((a) => a.toLowerCase().contains(q)) ||
        (group?.toLowerCase().contains(q) ?? false);
  }
}

/// "No group" for null/blank-safe display of stock groups.
String groupLabel(String? group) => (group == null || group.trim().isEmpty) ? 'No group' : group.trim();

enum StockSort {
  name('Name (A–Z)'),
  qtyAsc('Quantity (low to high)'),
  qtyDesc('Quantity (high to low)'),
  valueDesc('Stock value (high to low)');

  const StockSort(this.label);
  final String label;
}

/// Search, status and group filter of the inventory list.
class StockFilter {
  const StockFilter({this.query = '', this.status, this.group, this.sort = StockSort.name});

  final String query;

  /// Null = every status.
  final StockStatus? status;

  /// Null = every group; '' = items without a group.
  final String? group;
  final StockSort sort;

  bool get isFiltered => query.trim().isNotEmpty || status != null || group != null;

  /// [status] and [group] are wrapped in functions so they can be set to null.
  StockFilter copyWith({String? query, StockStatus? Function()? status, String? Function()? group, StockSort? sort}) =>
      StockFilter(
        query: query ?? this.query,
        status: status == null ? this.status : status(),
        group: group == null ? this.group : group(),
        sort: sort ?? this.sort,
      );
}

/// Applies [filter] to [items].
List<StockItem> filterStock(List<StockItem> items, StockFilter filter) {
  final out = items
      .where(
        (i) =>
            (filter.status == null || i.status == filter.status) &&
            (filter.group == null || (i.group?.trim() ?? '') == filter.group) &&
            i.matches(filter.query),
      )
      .toList();
  int byName(StockItem a, StockItem b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  int then(int c, StockItem a, StockItem b) => c != 0 ? c : byName(a, b);
  switch (filter.sort) {
    case StockSort.name:
      out.sort(byName);
    case StockSort.qtyAsc:
      out.sort((a, b) => then(a.closingQty.compareTo(b.closingQty), a, b));
    case StockSort.qtyDesc:
      out.sort((a, b) => then(b.closingQty.compareTo(a.closingQty), a, b));
    case StockSort.valueDesc:
      out.sort((a, b) => then((b.closingValue ?? Money.zero).compareTo(a.closingValue ?? Money.zero), a, b));
  }
  return out;
}

/// Distinct stock groups ('' for items without one), sorted.
List<String> stockGroups(List<StockItem> items) {
  final groups = {for (final i in items) i.group?.trim() ?? ''}.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return groups;
}

/// Totals over a list of items.
class StockSummary {
  const StockSummary({required this.items, required this.value, required this.byStatus, this.syncedAt});

  factory StockSummary.of(List<StockItem> items) {
    var value = Money.zero;
    final byStatus = {for (final s in StockStatus.values) s: 0};
    DateTime? synced;
    for (final i in items) {
      value += i.closingValue ?? Money.zero;
      byStatus[i.status] = byStatus[i.status]! + 1;
      final at = i.syncedAt;
      if (at != null && (synced == null || at.isAfter(synced))) synced = at;
    }
    return StockSummary(items: items.length, value: value, byStatus: byStatus, syncedAt: synced);
  }

  final int items;

  /// Sum of closing values; zero for staff (they don't load values).
  final Money value;
  final Map<StockStatus, int> byStatus;

  /// Most recent sync of any item.
  final DateTime? syncedAt;
}

/// One purchase bill containing a stock item (owner), the item's lines summed.
class ItemPurchase {
  const ItemPurchase({
    required this.purchaseId,
    required this.date,
    required this.supplierName,
    this.voucherNumber,
    required this.qty,
    this.unit,
    required this.rate,
    required this.amount,
  });

  factory ItemPurchase.fromJson(Map<String, dynamic> json) {
    final lines = (json['purchase_lines'] as List? ?? const []).cast<Map<String, dynamic>>();
    var qty = 0.0;
    var amount = Money.zero;
    for (final l in lines) {
      qty += parseQty(l['qty']);
      amount += Money.parse(l['amount']);
    }
    return ItemPurchase(
      purchaseId: json['id'] as String,
      date: parseDate(json['purchase_date'])!,
      supplierName: (json['supplier_name'] as String?) ?? '',
      voucherNumber: json['voucher_number'] as String?,
      qty: qty,
      unit: lines.isEmpty ? null : lines.first['unit'] as String?,
      rate: lines.isEmpty ? Money.zero : Money.parse(lines.first['rate']),
      amount: amount,
    );
  }

  final String purchaseId;
  final DateTime date;
  final String supplierName;
  final String? voucherNumber;
  final double qty;
  final String? unit;
  final Money rate;
  final Money amount;
}
