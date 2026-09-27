import 'package:intl/intl.dart';

/// Rupee amount held as integer paise. Money arithmetic never uses double.
///
/// Sign convention follows `shops.receivable` / `transactions.amount`:
/// positive = the shop owes the business (Dr), negative = in credit (Cr).
final class Money implements Comparable<Money> {
  const Money(this.paise);

  static const zero = Money(0);

  final int paise;

  /// Parses a PostgREST `numeric` value, which arrives as a JSON number or a
  /// string. Strings are parsed digit by digit so nothing is lost to floating point.
  factory Money.parse(Object? value) {
    if (value == null) return zero;
    if (value is int) return Money(value * 100);
    if (value is num) return Money((value * 100).round());
    if (value is String) return Money(_parseString(value));
    throw FormatException('Not a money value: $value');
  }

  /// A Tally-style absolute amount with its side ('DR' / 'CR' / '').
  factory Money.fromSide(Object? amount, String? side) {
    final abs = Money.parse(amount).abs();
    return side == 'CR' ? -abs : abs;
  }

  static int _parseString(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return 0;
    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    final parts = s.split('.');
    if (parts.length > 2 || parts.any((p) => !RegExp(r'^\d*$').hasMatch(p))) {
      throw FormatException('Not a money value: $raw');
    }
    final rupees = parts[0].isEmpty ? 0 : int.parse(parts[0]);
    var frac = parts.length == 2 ? parts[1] : '';
    // numeric(14,2) never has more than 2 decimals; round half up if it ever does.
    var extraRound = 0;
    if (frac.length > 2) {
      extraRound = int.parse(frac[2]) >= 5 ? 1 : 0;
      frac = frac.substring(0, 2);
    }
    final paise = rupees * 100 + int.parse(frac.padRight(2, '0')) + extraRound;
    return negative ? -paise : paise;
  }

  bool get isZero => paise == 0;
  bool get isNegative => paise < 0;
  bool get isPositive => paise > 0;

  Money abs() => Money(paise.abs());
  Money operator +(Money other) => Money(paise + other.paise);
  Money operator -(Money other) => Money(paise - other.paise);
  Money operator -() => Money(-paise);
  bool operator >(Money other) => paise > other.paise;
  bool operator <(Money other) => paise < other.paise;

  /// Dr when positive, Cr when negative, null when zero.
  BalanceSide? get side => paise > 0
      ? BalanceSide.dr
      : paise < 0
      ? BalanceSide.cr
      : null;

  @override
  int compareTo(Money other) => paise.compareTo(other.paise);

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;

  @override
  String toString() => formatInr(this);
}

enum BalanceSide {
  dr('Dr'),
  cr('Cr');

  const BalanceSide(this.label);
  final String label;
}

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _inrPlain = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 2);

/// `₹34,18,745.27` (lakh/crore grouping); negative values get a leading minus.
String formatInr(Money m) {
  final formatted = _inr.format(m.paise.abs() / 100);
  return m.isNegative ? '-$formatted' : formatted;
}

/// `Rs. 34,18,745.27`, for outputs whose font lacks the rupee sign (PDF).
String formatInrPlain(Money m) {
  final formatted = _inrPlain.format(m.paise.abs() / 100);
  return m.isNegative ? '-$formatted' : formatted;
}

/// Absolute amount with its side, e.g. `₹1,76,499.68 Cr`. Zero shows as `₹0.00`.
String formatBalance(Money m) {
  final side = m.side;
  final amount = formatInr(m.abs());
  return side == null ? amount : '$amount ${side.label}';
}

/// Short form for tiles: `₹34.2 L`, `₹1.5 crore`, `₹12.3 K`, `₹950`. Crore is
/// spelled out so it can't be mistaken for Cr (credit).
String formatInrCompact(Money m) {
  final sign = m.isNegative ? '-' : '';
  final rupees = m.paise.abs() / 100;
  String scaled(double v, String unit) {
    final text = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$sign₹${text.endsWith('.0') ? text.substring(0, text.length - 2) : text} $unit';
  }

  if (rupees >= 1e7) return scaled(rupees / 1e7, 'crore');
  if (rupees >= 1e5) return scaled(rupees / 1e5, 'L');
  if (rupees >= 1e3) return scaled(rupees / 1e3, 'K');
  return '$sign₹${rupees.round()}';
}
