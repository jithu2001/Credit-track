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

/// Shops that owe the business, grouped by site with subtotals.
class OutstandingReport {
  const OutstandingReport({required this.companyName, required this.generatedAt, required this.groups, required this.total});

  final String companyName;
  final DateTime generatedAt;

  /// Sites A–Z, "No site" last.
  final List<SiteGroup> groups;
  final Money total;

  int get shopCount => groups.fold(0, (n, g) => n + g.shops.length);
}

OutstandingReport buildOutstandingReport({
  required String companyName,
  required List<ShopSummary> shops,
  required DateTime generatedAt,
}) {
  final groups = [
    for (final (id, name, list) in groupBySite(shops.where((s) => s.receivable.isPositive), (s) => s.siteId, (s) => s.siteName))
      SiteGroup(
        id,
        name,
        list..sort((a, b) => b.receivable.compareTo(a.receivable)),
        list.fold(Money.zero, (sum, s) => sum + s.receivable),
      ),
  ];
  final total = groups.fold(Money.zero, (sum, g) => sum + g.subtotal);
  return OutstandingReport(companyName: companyName, generatedAt: generatedAt, groups: groups, total: total);
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
