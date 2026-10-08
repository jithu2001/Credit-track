import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_json.dart';

part 'statement.freezed.dart';
part 'statement.g.dart';

enum TxnCategory {
  @JsonValue('sales')
  sales('Sales'),
  @JsonValue('receipts')
  receipts('Receipts'),
  @JsonValue('returns')
  returns('Returns'),
  @JsonValue('adjustments')
  adjustments('Adjustments');

  const TxnCategory(this.label);
  final String label;
}

/// A row of `transactions`: one voucher's effect on one shop.
@freezed
abstract class ShopTransaction with _$ShopTransaction {
  const factory ShopTransaction({
    required String id,
    required DateTime transactionDate,
    String? voucherNumber,
    String? voucherType,
    @JsonKey(unknownEnumValue: TxnCategory.adjustments) @Default(TxnCategory.adjustments) TxnCategory category,
    String? narration,
    @MoneyConverter() @Default(Money.zero) Money debit,
    @MoneyConverter() @Default(Money.zero) Money credit,

    /// Signed effect on receivable = debit - credit.
    @MoneyConverter() @Default(Money.zero) Money amount,
    DateTime? createdAt,
  }) = _ShopTransaction;

  factory ShopTransaction.fromJson(Map<String, dynamic> json) => _$ShopTransactionFromJson(json);

  static const columns = 'id,transaction_date,voucher_number,voucher_type,category,narration,debit,credit,amount,created_at';
}

class StatementLine {
  const StatementLine(this.transaction, this.balanceAfter);

  final ShopTransaction transaction;

  /// Shop balance after this voucher (signed, Dr positive).
  final Money balanceAfter;
}

/// A shop's statement: running balances from the opening balance, and a
/// check that opening + movements equals the synced closing balance.
class Statement {
  const Statement({required this.opening, required this.closing, required this.computedClosing, required this.newestFirst});

  /// `GET /api/v1/shops/{id}/statement` (no dates): the whole ledger, worked out on the server.
  factory Statement.fromJson(Map<String, dynamic> j) => Statement(
    opening: Money.parse(j['ledger_opening']),
    closing: Money.parse(j['tally_balance']),
    computedClosing: Money.parse(j['computed_balance']),
    newestFirst: _lines(j),
  );

  final Money opening;

  /// `shops.receivable` as synced from Tally.
  final Money closing;

  /// opening + sum of active transactions.
  final Money computedClosing;

  final List<StatementLine> newestFirst;

  bool get reconciled => computedClosing == closing;
  Money get difference => closing - computedClosing;

  /// Lines passing the category and date filters; balances stay those of the full ledger.
  List<StatementLine> filtered({Set<TxnCategory> categories = const {}, DateTime? from, DateTime? to}) {
    return newestFirst.where((l) {
      final t = l.transaction;
      if (categories.isNotEmpty && !categories.contains(t.category)) return false;
      final d = DateTime(t.transactionDate.year, t.transactionDate.month, t.transactionDate.day);
      if (from != null && d.isBefore(DateTime(from.year, from.month, from.day))) return false;
      if (to != null && d.isAfter(DateTime(to.year, to.month, to.day))) return false;
      return true;
    }).toList();
  }
}

List<StatementLine> _lines(Map<String, dynamic> j) => [
  for (final l in (j['lines'] as List? ?? const []).cast<Map<String, dynamic>>())
    StatementLine(ShopTransaction.fromJson(l), Money.parse(l['balance_after'])),
];

/// A shop's statement for a period, as sent to the customer: the balance
/// brought forward, the period's vouchers oldest first, and the balance at the
/// end. Unlike [Statement.filtered], the balances are those of the period.
class PeriodStatement {
  const PeriodStatement({
    required this.from,
    required this.to,
    required this.opening,
    required this.lines,
    required this.closing,
    this.reconciled = true,
    this.tallyBalance = Money.zero,
  });

  /// `GET /api/v1/shops/{id}/statement?from=&to=`, worked out on the server.
  factory PeriodStatement.fromJson(Map<String, dynamic> j) => PeriodStatement(
    from: j['from'] == null ? null : DateTime.parse(j['from'] as String),
    to: j['to'] == null ? null : DateTime.parse(j['to'] as String),
    opening: Money.parse(j['opening']),
    lines: _lines(j).reversed.toList(),
    closing: Money.parse(j['closing']),
    reconciled: j['reconciled'] != false,
    tallyBalance: Money.parse(j['tally_balance']),
  );

  /// Null = from the first voucher / up to the last.
  final DateTime? from;
  final DateTime? to;

  /// Balance brought forward (signed, Dr positive).
  final Money opening;

  /// Oldest first.
  final List<StatementLine> lines;
  final Money closing;

  /// Whether the shop's whole ledger adds up to its Tally balance ([tallyBalance]).
  final bool reconciled;
  final Money tallyBalance;

  Money get totalDebit => lines.fold(Money.zero, (sum, l) => sum + l.transaction.debit);
  Money get totalCredit => lines.fold(Money.zero, (sum, l) => sum + l.transaction.credit);
}
