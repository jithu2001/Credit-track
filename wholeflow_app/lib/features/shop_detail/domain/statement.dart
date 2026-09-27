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

/// Builds the statement from transactions in any order.
Statement buildStatement({required Money opening, required Money closing, required List<ShopTransaction> transactions}) {
  final chronological = [...transactions]..sort(_chronological);
  var running = opening;
  final lines = <StatementLine>[];
  for (final t in chronological) {
    running += t.amount;
    lines.add(StatementLine(t, running));
  }
  return Statement(
    opening: opening,
    closing: closing,
    computedClosing: running,
    newestFirst: lines.reversed.toList(growable: false),
  );
}

int _chronological(ShopTransaction a, ShopTransaction b) {
  final byDate = a.transactionDate.compareTo(b.transactionDate);
  if (byDate != 0) return byDate;
  final ac = a.createdAt, bc = b.createdAt;
  if (ac != null && bc != null && ac != bc) return ac.compareTo(bc);
  return (a.voucherNumber ?? '').compareTo(b.voucherNumber ?? '');
}
