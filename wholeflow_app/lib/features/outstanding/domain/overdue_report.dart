import '../../../core/format.dart';
import '../../../core/money/money.dart';

/// An unpaid bill past the credit period, from `overdue_shops()`.
class OverdueBill {
  const OverdueBill({required this.date, required this.amount, required this.remaining, required this.daysOverdue, this.voucher});

  factory OverdueBill.fromJson(Map<String, dynamic> json) => OverdueBill(
    date: DateTime.parse(json['date'] as String),
    voucher: json['voucher'] as String?,
    amount: Money.parse(json['amount']),
    remaining: Money.parse(json['remaining']),
    daysOverdue: (json['days_overdue'] as num).toInt(),
  );

  final DateTime date;

  /// "Sales · 1024", or "Opening balance".
  final String? voucher;
  final Money amount;

  /// What is still unpaid after FIFO.
  final Money remaining;

  /// Days past the credit period.
  final int daysOverdue;
}

/// A shop with bills past the credit period.
class OverdueShop {
  const OverdueShop({
    required this.id,
    required this.name,
    required this.receivable,
    required this.overdue,
    required this.maxDaysOverdue,
    required this.billCount,
    this.area,
    this.phone,
    this.bills,
  });

  factory OverdueShop.fromJson(Map<String, dynamic> json) => OverdueShop(
    id: json['shop_id'] as String,
    name: json['name'] as String,
    area: json['area'] as String?,
    phone: json['phone'] as String?,
    receivable: Money.parse(json['receivable']),
    overdue: Money.parse(json['overdue']),
    maxDaysOverdue: (json['max_days_overdue'] as num).toInt(),
    billCount: (json['overdue_bills'] as num).toInt(),
    bills: json['bills_visible'] == true && json['bills'] is List
        ? [for (final b in json['bills'] as List) OverdueBill.fromJson(b as Map<String, dynamic>)]
        : null,
  );

  static const columns = 'shop_id,name,area,phone,receivable,overdue,max_days_overdue,overdue_bills,bills_visible,bills';

  final String id;
  final String name;
  final String? area;
  final String? phone;

  /// Everything the shop owes, overdue or not.
  final Money receivable;
  final Money overdue;

  /// Days the oldest overdue bill is past the credit period.
  final int maxDaysOverdue;
  final int billCount;

  /// Oldest first; null when the user may not see transactions.
  final List<OverdueBill>? bills;
}

class OverdueAreaGroup {
  const OverdueAreaGroup(this.area, this.shops, this.subtotal);

  final String area;

  /// Most overdue amount first.
  final List<OverdueShop> shops;
  final Money subtotal;
}

/// Shops past the credit period, grouped by area with subtotals.
class OverdueReport {
  const OverdueReport({
    required this.companyName,
    required this.creditDays,
    required this.generatedAt,
    required this.groups,
    required this.total,
  });

  final String companyName;
  final int creditDays;
  final DateTime generatedAt;

  /// Areas A–Z, "No area" last.
  final List<OverdueAreaGroup> groups;
  final Money total;

  int get shopCount => groups.fold(0, (n, g) => n + g.shops.length);

  /// Whether bill details came back (owner, or staff allowed to see transactions).
  bool get showsBills => groups.any((g) => g.shops.any((s) => s.bills != null));
}

OverdueReport buildOverdueReport({
  required String companyName,
  required int creditDays,
  required List<OverdueShop> shops,
  required DateTime generatedAt,
}) {
  final byArea = <String, List<OverdueShop>>{};
  for (final s in shops.where((s) => s.overdue.isPositive)) {
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
  final groups = <OverdueAreaGroup>[];
  for (final name in names) {
    final list = byArea[name]!
      ..sort((a, b) {
        final c = b.overdue.compareTo(a.overdue);
        return c != 0 ? c : b.maxDaysOverdue.compareTo(a.maxDaysOverdue);
      });
    final subtotal = list.fold(Money.zero, (sum, s) => sum + s.overdue);
    total += subtotal;
    groups.add(OverdueAreaGroup(name, list, subtotal));
  }
  return OverdueReport(companyName: companyName, creditDays: creditDays, generatedAt: generatedAt, groups: groups, total: total);
}

/// "20 days past limit".
String daysPastLimit(int days) => '${plural(days, 'day')} past limit';

/// Plain-text summary for the share sheet (WhatsApp friendly). Bills are
/// listed only when the report has them.
String overdueReportText(OverdueReport r) {
  final b = StringBuffer()
    ..writeln('Past ${plural(r.creditDays, 'day')} credit — ${r.companyName}')
    ..writeln('As of ${formatDateTime(r.generatedAt)}')
    ..writeln('Overdue: ${formatInr(r.total)} (${plural(r.shopCount, 'shop')})')
    ..writeln();
  for (final g in r.groups) {
    b.writeln('${g.area} — ${formatInr(g.subtotal)}');
    for (final s in g.shops) {
      b.writeln('  • ${s.name}: ${formatInr(s.overdue)} · ${daysPastLimit(s.maxDaysOverdue)}');
      for (final bill in s.bills ?? const <OverdueBill>[]) {
        b.writeln(
          '      ${bill.voucher ?? 'Bill'} (${formatDate(bill.date)}): '
          '${formatInr(bill.remaining)} due · ${daysPastLimit(bill.daysOverdue)}',
        );
      }
    }
    b.writeln();
  }
  return b.toString().trimRight();
}
