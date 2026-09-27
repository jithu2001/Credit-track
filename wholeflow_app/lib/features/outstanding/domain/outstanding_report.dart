import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../shops/domain/shop.dart';

class AreaGroup {
  const AreaGroup(this.area, this.shops, this.subtotal);

  final String area;

  /// Highest dues first.
  final List<ShopSummary> shops;
  final Money subtotal;
}

/// Shops that owe the business, grouped by area with subtotals.
class OutstandingReport {
  const OutstandingReport({required this.companyName, required this.generatedAt, required this.groups, required this.total});

  final String companyName;
  final DateTime generatedAt;

  /// Areas A–Z, "No area" last.
  final List<AreaGroup> groups;
  final Money total;

  int get shopCount => groups.fold(0, (n, g) => n + g.shops.length);
}

OutstandingReport buildOutstandingReport({
  required String companyName,
  required List<ShopSummary> shops,
  required DateTime generatedAt,
}) {
  final byArea = <String, List<ShopSummary>>{};
  for (final s in shops.where((s) => s.receivable.isPositive)) {
    byArea.putIfAbsent(areaLabel(s.area), () => []).add(s);
  }
  const noArea = 'No area';
  final names = byArea.keys.toList()
    ..sort((a, b) {
      if (a == noArea) return 1;
      if (b == noArea) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  var total = Money.zero;
  final groups = <AreaGroup>[];
  for (final name in names) {
    final list = byArea[name]!..sort((a, b) => b.receivable.compareTo(a.receivable));
    final subtotal = list.fold(Money.zero, (sum, s) => sum + s.receivable);
    total += subtotal;
    groups.add(AreaGroup(name, list, subtotal));
  }
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
    b.writeln('${g.area} — ${formatInr(g.subtotal)}');
    for (final s in g.shops) {
      b.writeln('  • ${s.name}: ${formatInr(s.receivable)}');
    }
    b.writeln();
  }
  return b.toString().trimRight();
}
