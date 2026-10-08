import '../../../core/money/money.dart';

/// An owner-made group of shops in one company (`sites`). A shop is in at
/// most one site; staff are given sites (or the full company).
class Site {
  const Site({required this.id, required this.companyId, required this.name});

  factory Site.fromJson(Map<String, dynamic> json) =>
      Site(id: json['id'] as String, companyId: json['company_id'] as String, name: (json['name'] as String?) ?? '');

  static const columns = 'id,company_id,name';

  final String id;
  final String companyId;
  final String name;
}

/// "Town" for a site name; shops in no site read "No site".
String siteLabel(String? name) => (name == null || name.trim().isEmpty) ? 'No site' : name.trim();

/// One row of `site_report()`: a site's shops and money for a period. The
/// row with a null [siteId] is the shops in no site. Sales, returns and
/// collections are null when the caller may not see transactions.
class SiteReportRow {
  const SiteReportRow({
    required this.siteId,
    required this.siteName,
    required this.shops,
    required this.shopsWithDues,
    required this.outstanding,
    required this.advance,
    this.sales,
    this.returns,
    this.collections,
  });

  factory SiteReportRow.fromJson(Map<String, dynamic> json) {
    Money? optional(Object? v) => v == null ? null : Money.parse(v);
    return SiteReportRow(
      siteId: json['site_id'] as String?,
      siteName: json['site_name'] as String?,
      shops: (json['shops'] as num?)?.toInt() ?? 0,
      shopsWithDues: (json['shops_with_dues'] as num?)?.toInt() ?? 0,
      outstanding: Money.parse(json['outstanding']),
      advance: Money.parse(json['advance']),
      sales: optional(json['sales']),
      returns: optional(json['returns']),
      collections: optional(json['collections']),
    );
  }

  final String? siteId;
  final String? siteName;
  final int shops;
  final int shopsWithDues;
  final Money outstanding;
  final Money advance;
  final Money? sales;
  final Money? returns;
  final Money? collections;

  bool get isNoSite => siteId == null;
  String get label => siteLabel(siteName);
}

/// A shop as the site editor needs it: which site it is in now.
class SiteShop {
  const SiteShop({required this.id, required this.name, this.area, this.siteId, this.receivable = Money.zero});

  factory SiteShop.fromJson(Map<String, dynamic> json) => SiteShop(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? '',
    area: json['area'] as String?,
    siteId: json['site_id'] as String?,
    receivable: Money.parse(json['receivable']),
  );

  static const columns = 'id,name,area,site_id,receivable';

  final String id;
  final String name;
  final String? area;
  final String? siteId;
  final Money receivable;
}

/// The period of the site report.
enum ReportPeriod {
  thisMonth('This month'),
  lastMonth('Last month'),
  last3Months('Last 3 months'),
  thisYear('This financial year');

  const ReportPeriod(this.label);
  final String label;

  /// Inclusive date range for [today]. The financial year starts on 1 April.
  (DateTime, DateTime) range(DateTime today) {
    final d = DateTime(today.year, today.month, today.day);
    return switch (this) {
      thisMonth => (DateTime(d.year, d.month), d),
      lastMonth => (DateTime(d.year, d.month - 1), DateTime(d.year, d.month, 0)),
      last3Months => (DateTime(d.year, d.month - 2), d),
      thisYear => (DateTime(d.month >= 4 ? d.year : d.year - 1, 4), d),
    };
  }
}
