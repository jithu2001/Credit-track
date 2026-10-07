import '../../../core/format.dart';
import '../../../core/money/money.dart';

/// A purchase bill as shown in lists.
class PurchaseSummary {
  const PurchaseSummary({
    required this.id,
    required this.date,
    required this.supplierName,
    this.supplierId,
    this.voucherNumber,
    this.voucherType,
    this.supplierBillNumber,
    this.taxable = Money.zero,
    this.total = Money.zero,
    this.lineCount = 0,
  });

  static const columns =
      'id,purchase_date,supplier_id,supplier_name,voucher_number,voucher_type,supplier_bill_number,'
      'taxable_amount,total_amount,line_count';

  factory PurchaseSummary.fromJson(Map<String, dynamic> json) => PurchaseSummary(
    id: json['id'] as String,
    date: parseDate(json['purchase_date'])!,
    supplierId: json['supplier_id'] as String?,
    supplierName: (json['supplier_name'] as String?) ?? '',
    voucherNumber: json['voucher_number'] as String?,
    voucherType: json['voucher_type'] as String?,
    supplierBillNumber: json['supplier_bill_number'] as String?,
    taxable: Money.parse(json['taxable_amount']),
    total: Money.parse(json['total_amount']),
    lineCount: (json['line_count'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final DateTime date;

  /// Null when the party ledger isn't under the synced supplier groups.
  final String? supplierId;

  /// Party ledger name as in Tally.
  final String supplierName;
  final String? voucherNumber;
  final String? voucherType;

  /// The supplier's own bill number (Tally "Reference").
  final String? supplierBillNumber;
  final Money taxable;
  final Money total;
  final int lineCount;

  String get supplierLabel => supplierName.trim().isEmpty ? 'Unknown supplier' : supplierName.trim();
}

/// An item line of a purchase bill.
class PurchaseLine {
  const PurchaseLine({
    required this.lineNo,
    required this.itemName,
    this.stockItemId,
    this.godown,
    this.qty = 0,
    this.actualQty = 0,
    this.unit,
    this.rate = Money.zero,
    this.discountPercent = 0,
    this.amount = Money.zero,
  });

  static const columns = 'line_no,stock_item_id,item_name,godown,qty,actual_qty,unit,rate,discount_percent,amount';

  factory PurchaseLine.fromJson(Map<String, dynamic> json) => PurchaseLine(
    lineNo: (json['line_no'] as num?)?.toInt() ?? 0,
    stockItemId: json['stock_item_id'] as String?,
    itemName: (json['item_name'] as String?) ?? '',
    godown: json['godown'] as String?,
    qty: parseQty(json['qty']),
    actualQty: parseQty(json['actual_qty']),
    unit: json['unit'] as String?,
    rate: Money.parse(json['rate']),
    discountPercent: parseQty(json['discount_percent']),
    amount: Money.parse(json['amount']),
  );

  final int lineNo;
  final String itemName;
  final String? stockItemId;
  final String? godown;

  /// Billed quantity.
  final double qty;
  final double actualQty;
  final String? unit;
  final Money rate;
  final double discountPercent;
  final Money amount;
}

/// A non-item entry of a bill (GST, TCS, freight, round off). Positive when it
/// adds to the bill (Tally Dr), negative when it reduces it (Cr).
class PurchaseLedgerEntry {
  const PurchaseLedgerEntry({required this.ledger, required this.amount});

  factory PurchaseLedgerEntry.fromJson(Map<String, dynamic> json) => PurchaseLedgerEntry(
    ledger: (json['ledger'] as String?) ?? '',
    // fromSide makes CR negative; DR (and '') stays positive.
    amount: Money.fromSide(json['amount'], json['type'] as String?),
  );

  final String ledger;
  final Money amount;
}

/// A purchase bill with its lines, for the detail screen.
class PurchaseDetail {
  const PurchaseDetail({
    required this.summary,
    this.narration,
    this.taxAndOther = Money.zero,
    this.totalQty = 0,
    this.ledgerEntries = const [],
    this.lines = const [],
    this.syncedAt,
  });

  static const columns =
      '${PurchaseSummary.columns},narration,tax_and_other_amount,total_qty,ledger_entries,synced_at,'
      'purchase_lines(${PurchaseLine.columns})';

  factory PurchaseDetail.fromJson(Map<String, dynamic> json) {
    final lines = [
      for (final l in (json['purchase_lines'] as List? ?? const [])) PurchaseLine.fromJson(l as Map<String, dynamic>),
    ]..sort((a, b) => a.lineNo.compareTo(b.lineNo));
    return PurchaseDetail(
      summary: PurchaseSummary.fromJson(json),
      narration: json['narration'] as String?,
      taxAndOther: Money.parse(json['tax_and_other_amount']),
      totalQty: parseQty(json['total_qty']),
      ledgerEntries: [
        for (final e in (json['ledger_entries'] as List? ?? const [])) PurchaseLedgerEntry.fromJson(e as Map<String, dynamic>),
      ],
      lines: lines,
      syncedAt: json['synced_at'] == null ? null : DateTime.tryParse(json['synced_at'] as String),
    );
  }

  final PurchaseSummary summary;
  final String? narration;
  final Money taxAndOther;
  final double totalQty;
  final List<PurchaseLedgerEntry> ledgerEntries;
  final List<PurchaseLine> lines;
  final DateTime? syncedAt;
}

/// Purchase totals of one calendar month.
class MonthPurchases {
  const MonthPurchases({required this.month, required this.bills, required this.total});

  final DateTime month;
  final int bills;
  final Money total;
}

/// Sums `v_purchases_by_supplier_month` rows (one per supplier and month)
/// into one total per month, newest first.
List<MonthPurchases> monthTotalsOf(List<Map<String, dynamic>> rows) {
  final bills = <DateTime, int>{};
  final totals = <DateTime, Money>{};
  for (final r in rows) {
    final month = parseDate(r['month']);
    if (month == null) continue;
    bills[month] = (bills[month] ?? 0) + ((r['bills'] as num?)?.toInt() ?? 0);
    totals[month] = (totals[month] ?? Money.zero) + Money.parse(r['total_amount']);
  }
  final months = bills.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final m in months) MonthPurchases(month: m, bills: bills[m]!, total: totals[m]!)];
}

/// Which bills a purchase list shows. A record, so equal queries share a provider.
typedef PurchaseQuery = ({String companyId, String search, String? supplierId});
