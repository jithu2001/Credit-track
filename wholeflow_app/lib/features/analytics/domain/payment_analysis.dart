import '../../../core/money/money.dart';
import '../../shop_detail/domain/statement.dart';

/// Payment behaviour of shops, computed on the device from synced data.
///
/// Every credit (receipt, return, credit adjustment) settles the **oldest open
/// bill first** (FIFO). A bill is due `creditDays` after its date. The shop's
/// opening balance counts as one bill dated where the synced vouchers begin
/// (the current Tally period); a Cr opening balance is an advance. Credits that find no open bill wait as an
/// advance and settle the next bills as they arrive.
///
/// Only receipts count as *paying* for the timing figures (days to pay,
/// on time); returns and adjustments still settle bills.

/// One voucher line of a shop, as needed for the analysis.
class PaymentTxn {
  const PaymentTxn({
    required this.shopId,
    required this.date,
    required this.category,
    required this.debit,
    required this.credit,
    this.voucher,
    this.createdAt,
  });

  final String shopId;
  final DateTime date;
  final TxnCategory category;
  final Money debit;
  final Money credit;
  final String? voucher;
  final DateTime? createdAt;
}

class ShopOpening {
  const ShopOpening({
    required this.id,
    required this.name,
    this.area,
    this.phone,
    required this.opening,
    required this.receivable,
  });

  final String id;
  final String name;
  final String? area;
  final String? phone;

  /// Signed: Dr (owes) positive.
  final Money opening;
  final Money receivable;
}

enum SettleKind { payment, returned, adjustment }

class Allocation {
  const Allocation(this.date, this.amount, this.kind);

  final DateTime date;
  final Money amount;
  final SettleKind kind;
}

class Bill {
  Bill({required this.date, required this.amount, required this.due, this.voucher, this.isOpening = false}) : remaining = amount;

  final DateTime date;
  final Money amount;
  final DateTime due;
  final String? voucher;
  final bool isOpening;

  Money remaining;
  DateTime? settledOn;
  final List<Allocation> allocations = [];

  bool get isOpen => remaining.isPositive;

  /// Settled by at least one receipt (not only returns/adjustments).
  bool get paidByReceipt => allocations.any((a) => a.kind == SettleKind.payment);

  bool get settledOnTime => settledOn != null && !settledOn!.isAfter(due);

  /// Days past due today (0 when not yet due).
  int daysOverdue(DateTime today) => today.isAfter(due) ? today.difference(due).inDays : 0;
}

/// Ageing of open amounts by days past due.
enum AgeBucket {
  notDue('Not due yet'),
  d1to30('1–30 days late'),
  d31to60('31–60 days late'),
  d61to90('61–90 days late'),
  d90plus('Over 90 days late');

  const AgeBucket(this.label);
  final String label;

  static AgeBucket of(int daysOverdue) => switch (daysOverdue) {
    <= 0 => notDue,
    <= 30 => d1to30,
    <= 60 => d31to60,
    <= 90 => d61to90,
    _ => d90plus,
  };
}

enum PaymentStatus {
  onTrack('On track'),
  slightlyLate('Slightly late'),
  late('Late'),
  veryLate('Very late');

  const PaymentStatus(this.label);
  final String label;

  static PaymentStatus of(int maxDaysOverdue) => switch (maxDaysOverdue) {
    <= 0 => onTrack,
    <= 30 => slightlyLate,
    <= 60 => late,
    _ => veryLate,
  };
}

/// How a shop usually pays, judged by its average days from bill to payment
/// against the credit period.
enum PayHabit {
  onTime('Pays on time'),
  late('Pays late'),
  veryLate('Pays very late'),
  noPayments('No payments yet');

  const PayHabit(this.label);
  final String label;

  /// Within the period is on time; up to 30 days more is late; beyond that very late.
  static PayHabit of(double? avgDaysToPay, int creditDays) {
    if (avgDaysToPay == null) return noPayments;
    final d = avgDaysToPay.round();
    if (d <= creditDays) return onTime;
    if (d <= creditDays + 30) return late;
    return veryLate;
  }
}

class ShopPaymentProfile {
  ShopPaymentProfile({
    required this.shop,
    required this.bills,
    required this.advance,
    required this.today,
    required this.lastPaymentDate,
    required this.lastPaymentAmount,
    required this.avgDaysToPay,
    required this.avgDaysLate,
  });

  final ShopOpening shop;

  /// All bills, oldest first.
  final List<Bill> bills;

  /// Credit not yet used against any bill.
  final Money advance;
  final DateTime today;
  final DateTime? lastPaymentDate;
  final Money lastPaymentAmount;

  /// Receipt-weighted average days from bill date to payment; null without receipts.
  final double? avgDaysToPay;

  /// Receipt-weighted average days paid after the due date (early counts as 0).
  final double? avgDaysLate;

  List<Bill> get openBills => bills.where((b) => b.isOpen).toList();

  Money get openAmount => bills.fold(Money.zero, (s, b) => s + b.remaining);

  Money get overdue => bills.where((b) => b.isOpen && b.daysOverdue(today) > 0).fold(Money.zero, (s, b) => s + b.remaining);

  /// Days past due of the oldest overdue bill (0 when nothing is overdue).
  int get maxDaysOverdue => bills.where((b) => b.isOpen).fold(0, (m, b) => b.daysOverdue(today) > m ? b.daysOverdue(today) : m);

  DateTime? get oldestOpenBillDate {
    for (final b in bills) {
      if (b.isOpen) return b.date;
    }
    return null;
  }

  Map<AgeBucket, Money> get ageing {
    final out = {for (final k in AgeBucket.values) k: Money.zero};
    for (final b in bills.where((b) => b.isOpen)) {
      final k = AgeBucket.of(b.daysOverdue(today));
      out[k] = out[k]! + b.remaining;
    }
    return out;
  }

  /// Bills fully settled with at least one receipt.
  List<Bill> get paidBills => bills.where((b) => !b.isOpen && b.paidByReceipt).toList();

  int get onTimeCount => paidBills.where((b) => b.settledOnTime).length;

  /// Share of paid bills settled by their due date; null when none are paid yet.
  double? get onTimeRate => paidBills.isEmpty ? null : onTimeCount / paidBills.length;

  PaymentStatus get status => PaymentStatus.of(maxDaysOverdue);

  PayHabit habit(int creditDays) => PayHabit.of(avgDaysToPay, creditDays);

  /// Open bills minus advance; equals the synced balance when the data is complete.
  Money get computedBalance => openAmount - advance;
  bool get reconciled => computedBalance == shop.receivable;

  bool get hasActivity => bills.isNotEmpty || advance.isPositive;
}

class BusinessPaymentSummary {
  const BusinessPaymentSummary({
    required this.shops,
    required this.creditDays,
    required this.today,
    required this.overdue,
    required this.overdueShops,
    required this.openAmount,
    required this.ageing,
    required this.onTimeRate,
    required this.avgDaysToPay,
  });

  final List<ShopPaymentProfile> shops;
  final int creditDays;
  final DateTime today;
  final Money overdue;
  final int overdueShops;
  final Money openAmount;
  final Map<AgeBucket, Money> ageing;
  final double? onTimeRate;
  final double? avgDaysToPay;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Runs FIFO for one shop.
ShopPaymentProfile analyseShop({
  required ShopOpening shop,
  required List<PaymentTxn> txns,
  required int creditDays,
  required DateTime booksFrom,
  required DateTime today,
}) {
  final day = _day(today);
  final bills = <Bill>[];
  // Advances waiting for a bill: (date, amount, kind), oldest first.
  final pool = <(DateTime, Money, SettleKind)>[];

  var paidWeighted = 0.0, lateWeighted = 0.0, paidTotal = 0.0;
  DateTime? lastPaymentDate;
  var lastPaymentAmount = Money.zero;

  void record(Bill bill, DateTime date, Money amount, SettleKind kind) {
    bill.allocations.add(Allocation(date, amount, kind));
    bill.remaining -= amount;
    if (!bill.isOpen) bill.settledOn = date.isBefore(bill.date) ? bill.date : date;
    if (kind == SettleKind.payment) {
      final paidOn = date.isBefore(bill.date) ? bill.date : date;
      final rupees = amount.paise / 100;
      paidWeighted += rupees * paidOn.difference(bill.date).inDays;
      final late = paidOn.difference(bill.due).inDays;
      lateWeighted += rupees * (late > 0 ? late : 0);
      paidTotal += rupees;
    }
  }

  void addBill(Bill bill) {
    bills.add(bill);
    // Settle straight away from any advance.
    while (bill.isOpen && pool.isNotEmpty) {
      final (date, amount, kind) = pool.first;
      final use = amount < bill.remaining ? amount : bill.remaining;
      record(bill, date, use, kind);
      final left = amount - use;
      if (left.isPositive) {
        pool[0] = (date, left, kind);
      } else {
        pool.removeAt(0);
      }
    }
  }

  void addCredit(DateTime date, Money amount, SettleKind kind) {
    var left = amount;
    for (final bill in bills) {
      if (!left.isPositive) break;
      if (!bill.isOpen) continue;
      final use = left < bill.remaining ? left : bill.remaining;
      record(bill, date, use, kind);
      left -= use;
    }
    if (left.isPositive) pool.add((date, left, kind));
  }

  final start = _day(booksFrom);
  if (shop.opening.isPositive) {
    addBill(
      Bill(
        date: start,
        amount: shop.opening,
        due: start.add(Duration(days: creditDays)),
        isOpening: true,
        voucher: 'Opening balance',
      ),
    );
  } else if (shop.opening.isNegative) {
    pool.add((start, shop.opening.abs(), SettleKind.adjustment));
  }

  // Same day: bills before credits, so a same-day payment can settle that day's bill.
  final ordered = [...txns]
    ..sort((a, b) {
      final d = _day(a.date).compareTo(_day(b.date));
      if (d != 0) return d;
      final ab = a.debit.isPositive ? 0 : 1, bb = b.debit.isPositive ? 0 : 1;
      if (ab != bb) return ab - bb;
      final ac = a.createdAt, bc = b.createdAt;
      return (ac != null && bc != null) ? ac.compareTo(bc) : 0;
    });

  for (final t in ordered) {
    final date = _day(t.date);
    if (t.debit.isPositive) {
      addBill(
        Bill(
          date: date,
          amount: t.debit,
          due: date.add(Duration(days: creditDays)),
          voucher: t.voucher,
        ),
      );
    }
    if (t.credit.isPositive) {
      final kind = switch (t.category) {
        TxnCategory.receipts => SettleKind.payment,
        TxnCategory.returns => SettleKind.returned,
        _ => SettleKind.adjustment,
      };
      if (kind == SettleKind.payment) {
        lastPaymentDate = date;
        lastPaymentAmount = t.credit;
      }
      addCredit(date, t.credit, kind);
    }
  }

  return ShopPaymentProfile(
    shop: shop,
    bills: bills,
    advance: pool.fold(Money.zero, (s, p) => s + p.$2),
    today: day,
    lastPaymentDate: lastPaymentDate,
    lastPaymentAmount: lastPaymentAmount,
    avgDaysToPay: paidTotal == 0 ? null : paidWeighted / paidTotal,
    avgDaysLate: paidTotal == 0 ? null : lateWeighted / paidTotal,
  );
}

/// Runs FIFO for every shop of a company and totals the results.
BusinessPaymentSummary analyseBusiness({
  required List<ShopOpening> shops,
  required List<PaymentTxn> txns,
  required int creditDays,
  required DateTime booksFrom,
  required DateTime today,
}) {
  final byShop = <String, List<PaymentTxn>>{};
  for (final t in txns) {
    byShop.putIfAbsent(t.shopId, () => []).add(t);
  }
  final profiles = [
    for (final s in shops)
      analyseShop(shop: s, txns: byShop[s.id] ?? const [], creditDays: creditDays, booksFrom: booksFrom, today: today),
  ].where((p) => p.hasActivity).toList();

  final ageing = {for (final k in AgeBucket.values) k: Money.zero};
  var overdue = Money.zero, open = Money.zero;
  var overdueShops = 0, paid = 0, onTime = 0;
  var weighted = 0.0, total = 0.0;
  for (final p in profiles) {
    final o = p.overdue;
    overdue += o;
    if (o.isPositive) overdueShops++;
    open += p.openAmount;
    p.ageing.forEach((k, v) => ageing[k] = ageing[k]! + v);
    paid += p.paidBills.length;
    onTime += p.onTimeCount;
    if (p.avgDaysToPay != null) {
      // Weight each shop's average by the receipts it made.
      final receipts = p.bills
          .expand((b) => b.allocations)
          .where((a) => a.kind == SettleKind.payment)
          .fold(0.0, (s, a) => s + a.amount.paise / 100);
      weighted += p.avgDaysToPay! * receipts;
      total += receipts;
    }
  }
  return BusinessPaymentSummary(
    shops: profiles,
    creditDays: creditDays,
    today: _day(today),
    overdue: overdue,
    overdueShops: overdueShops,
    openAmount: open,
    ageing: ageing,
    onTimeRate: paid == 0 ? null : onTime / paid,
    avgDaysToPay: total == 0 ? null : weighted / total,
  );
}

/// Overdue as it stood [daysAgo] days before [today], from the vouchers dated
/// up to then. Null when the synced books do not reach back that far.
Money? overdueDaysAgo({
  required List<ShopOpening> shops,
  required List<PaymentTxn> txns,
  required int creditDays,
  required DateTime booksFrom,
  required DateTime today,
  int daysAgo = 30,
}) {
  final then = _day(today).subtract(Duration(days: daysAgo));
  if (then.isBefore(_day(booksFrom))) return null;
  final earlier = [
    for (final t in txns)
      if (!_day(t.date).isAfter(then)) t,
  ];
  return analyseBusiness(shops: shops, txns: earlier, creditDays: creditDays, booksFrom: booksFrom, today: then).overdue;
}
