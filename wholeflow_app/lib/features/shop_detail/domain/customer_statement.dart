import '../../../core/format.dart';
import '../../../core/money/money.dart';
import '../../shops/domain/shop.dart';
import 'statement.dart';

/// A shop's statement of account to send to the customer: who it is from, who
/// it is for, and the period. Only what a customer should see: no site,
/// location, payment habits or Tally narrations (often internal notes).
class CustomerStatement {
  const CustomerStatement({required this.companyName, required this.shop, required this.period, required this.generatedAt});

  final String companyName;
  final ShopDetail shop;
  final PeriodStatement period;
  final DateTime generatedAt;

  String get periodLabel => statementPeriodLabel(period.from, period.to);

  /// The share subject, e.g. "Statement of account — TYRE HUB".
  String get subject => 'Statement of account — ${shop.name}';

  String get fileStem => 'statement-${fileSlug(shop.name)}-${_fileDate(period.to ?? generatedAt)}';
}

/// "1 Apr 2026 – 6 Oct 2026", "Up to 6 Oct 2026", "From 1 Apr 2026", "All transactions".
String statementPeriodLabel(DateTime? from, DateTime? to) => switch ((from, to)) {
  (null, null) => 'All transactions',
  (null, final DateTime t) => 'Up to ${formatDate(t)}',
  (final DateTime f, null) => 'From ${formatDate(f)}',
  (final DateTime f, final DateTime t) => '${formatDate(f)} – ${formatDate(t)}',
};

String _fileDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "Tally voucher type and number", e.g. "Sales 123".
String voucherLabel(ShopTransaction t) =>
    [t.voucherType, t.voucherNumber].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim()).join(' ');

/// The closing balance in words a customer reads: "Balance due" or "Advance".
String balanceCaption(Money m) => switch (m.side) {
  BalanceSide.dr => 'Balance due',
  BalanceSide.cr => 'Advance with us',
  null => 'Balance',
};

/// More entries than this and the text version gives totals only (the PDF
/// always lists every entry).
const statementTextMaxLines = 40;

/// Plain text for WhatsApp or SMS.
String customerStatementText(CustomerStatement c) {
  final p = c.period;
  final b = StringBuffer()
    ..writeln('Statement of account')
    ..writeln(c.shop.name)
    ..writeln('From: ${c.companyName}')
    ..writeln('Period: ${c.periodLabel}')
    ..writeln()
    ..writeln('Opening balance: ${formatBalance(p.opening)}');
  if (p.lines.isEmpty) {
    b.writeln('No transactions in this period.');
  } else if (p.lines.length > statementTextMaxLines) {
    b
      ..writeln('${plural(p.lines.length, 'entry', 'entries')} (ask for the PDF for details)')
      ..writeln('Debits: ${formatInr(p.totalDebit)}')
      ..writeln('Credits: ${formatInr(p.totalCredit)}');
  } else {
    b.writeln();
    for (final l in p.lines) {
      final t = l.transaction;
      final debit = t.debit.isPositive;
      final voucher = voucherLabel(t);
      b.writeln(
        '${formatDate(t.transactionDate)}${voucher.isEmpty ? '' : ' · $voucher'} · '
        '${debit ? 'Debit' : 'Credit'} ${formatInr(debit ? t.debit : t.credit)}',
      );
    }
    b.writeln();
  }
  b.writeln('${balanceCaption(p.closing)} as of ${formatDate(p.to ?? c.generatedAt)}: ${formatBalance(p.closing)}');
  return b.toString().trimRight();
}
