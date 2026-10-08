import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../shops/domain/shop.dart';
import '../../sites/domain/site.dart';

class SiteGroup {
  const SiteGroup(this.siteId, this.site, this.shops, this.subtotal);

  /// Null for the shops in no site.
  final String? siteId;
  final String site;

  /// Highest dues first.
  final List<ShopSummary> shops;
  final Money subtotal;
}

/// Shops that owe the business, grouped by site with subtotals
/// (`GET /api/v1/reports/outstanding`, grouped on the server).
class OutstandingReport {
  const OutstandingReport({required this.companyName, required this.generatedAt, required this.groups, required this.total});

  factory OutstandingReport.fromJson(Map<String, dynamic> j) => OutstandingReport(
    companyName: (j['company_name'] as String?) ?? '',
    generatedAt: DateTime.parse(j['generated_at'] as String).toLocal(),
    groups: [
      for (final g in (j['groups'] as List? ?? const []).cast<Map<String, dynamic>>())
        SiteGroup(g['site_id'] as String?, siteLabel(g['site_name'] as String?), [
          for (final s in (g['shops'] as List).cast<Map<String, dynamic>>()) ShopSummary.fromJson(s),
        ], Money.parse(g['subtotal'])),
    ],
    total: Money.parse(j['total']),
  );

  final String companyName;
  final DateTime generatedAt;

  /// Sites A–Z, "No site" last.
  final List<SiteGroup> groups;
  final Money total;

  int get shopCount => groups.fold(0, (n, g) => n + g.shops.length);

  /// Only the shops passing [keep] (the on-screen search), with totals recomputed.
  OutstandingReport narrowed(bool Function(ShopSummary) keep) {
    final kept = [
      for (final g in groups)
        if (g.shops.where(keep).toList() case final shops when shops.isNotEmpty)
          SiteGroup(g.siteId, g.site, shops, shops.fold(Money.zero, (sum, s) => sum + s.receivable)),
    ];
    return OutstandingReport(
      companyName: companyName,
      generatedAt: generatedAt,
      groups: kept,
      total: kept.fold(Money.zero, (sum, g) => sum + g.subtotal),
    );
  }
}

/// Plain-text summary for the share sheet (WhatsApp friendly).
String outstandingReportText(OutstandingReport r) {
  final b = StringBuffer()
    ..writeln('Outstanding — ${r.companyName}')
    ..writeln('As of ${formatDateTime(r.generatedAt)}')
    ..writeln('Total: ${formatInr(r.total)} (${r.shopCount} shops)')
    ..writeln();
  for (final g in r.groups) {
    b.writeln('${g.site} — ${formatInr(g.subtotal)}');
    for (final s in g.shops) {
      b.writeln('  • ${s.name}: ${formatInr(s.receivable)}');
    }
    b.writeln();
  }
  return b.toString().trimRight();
}
