import '../../../core/money/money.dart';

/// One calendar month of business, from `GET /api/v1/reports/monthly`.
class TrendMonth {
  const TrendMonth({
    required this.month,
    this.sales = Money.zero,
    this.bills = 0,
    this.returns = Money.zero,
    this.collections = Money.zero,
    this.buyers = 0,
    this.purchases = Money.zero,
    this.purchaseBills = 0,
  });

  factory TrendMonth.fromJson(Map<String, dynamic> j) => TrendMonth(
    month: DateTime.parse(j['month'] as String),
    sales: Money.parse(j['sales']),
    bills: (j['bills'] as num?)?.toInt() ?? 0,
    returns: Money.parse(j['returns']),
    collections: Money.parse(j['collections']),
    buyers: (j['buyers'] as num?)?.toInt() ?? 0,
    purchases: Money.parse(j['purchases']),
    purchaseBills: (j['purchase_bills'] as num?)?.toInt() ?? 0,
  );

  /// First day of the month.
  final DateTime month;

  /// Sales bills to shops.
  final Money sales;
  final int bills;
  final Money returns;

  /// Receipts from shops.
  final Money collections;

  /// Shops with at least one sales bill.
  final int buyers;
  final Money purchases;
  final int purchaseBills;
}

/// A shop that bought most over the trend's months.
class TopBuyer {
  const TopBuyer({
    required this.shopId,
    required this.name,
    this.siteName,
    required this.sales,
    required this.bills,
    required this.receivable,
  });

  factory TopBuyer.fromJson(Map<String, dynamic> j) => TopBuyer(
    shopId: j['shop_id'] as String,
    name: (j['name'] as String?) ?? '',
    siteName: j['site_name'] as String?,
    sales: Money.parse(j['sales']),
    bills: (j['bills'] as num?)?.toInt() ?? 0,
    receivable: Money.parse(j['receivable']),
  );

  final String shopId;
  final String name;
  final String? siteName;
  final Money sales;
  final int bills;

  /// What the shop owes now.
  final Money receivable;
}

/// The first days of an earlier month, matching how far the current month
/// has got (1–8 Oct when today is 8 Nov).
class SameDays {
  const SameDays({
    required this.from,
    required this.to,
    this.sales = Money.zero,
    this.collections = Money.zero,
    this.purchases = Money.zero,
  });

  factory SameDays.fromJson(Map<String, dynamic> j) => SameDays(
    from: DateTime.parse(j['from'] as String),
    to: DateTime.parse(j['to'] as String),
    sales: Money.parse(j['sales']),
    collections: Money.parse(j['collections']),
    purchases: Money.parse(j['purchases']),
  );

  final DateTime from;

  /// Last day included.
  final DateTime to;
  final Money sales;
  final Money collections;
  final Money purchases;
}

/// The owner's month-by-month view of the business.
class BusinessTrend {
  const BusinessTrend({required this.months, this.lastMonthSoFar, this.lastYearSoFar, required this.topBuyers});

  factory BusinessTrend.fromJson(Map<String, dynamic> j) {
    SameDays? days(String key) => j[key] is Map ? SameDays.fromJson((j[key] as Map).cast<String, dynamic>()) : null;
    return BusinessTrend(
      months: [for (final m in (j['months'] as List? ?? const []).cast<Map<String, dynamic>>()) TrendMonth.fromJson(m)],
      lastMonthSoFar: days('same_days_last_month'),
      lastYearSoFar: days('same_days_last_year'),
      topBuyers: [for (final b in (j['top_buyers'] as List? ?? const []).cast<Map<String, dynamic>>()) TopBuyer.fromJson(b)],
    );
  }

  /// Oldest first; the last one is the current month (so far).
  final List<TrendMonth> months;

  /// The same days of last month and of this month a year ago, to compare
  /// the current month with fairly.
  final SameDays? lastMonthSoFar;
  final SameDays? lastYearSoFar;
  final List<TopBuyer> topBuyers;
}

/// What the trend chart shows.
enum TrendMetric {
  sales('Sales'),
  collections('Collections'),
  purchases('Purchases');

  const TrendMetric(this.label);
  final String label;

  Money of(TrendMonth m) => switch (this) {
    TrendMetric.sales => m.sales,
    TrendMetric.collections => m.collections,
    TrendMetric.purchases => m.purchases,
  };

  Money ofDays(SameDays d) => switch (this) {
    TrendMetric.sales => d.sales,
    TrendMetric.collections => d.collections,
    TrendMetric.purchases => d.purchases,
  };
}

/// Percentage change from [before] to [now]; null when there is nothing to
/// compare with.
double? percentChange(Money now, Money before) {
  if (!before.isPositive) return null;
  return (now.paise - before.paise) * 100 / before.paise;
}
