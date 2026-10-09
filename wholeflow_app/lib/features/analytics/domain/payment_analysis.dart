import '../../../core/money/money.dart';

/// Payment behaviour of shops, worked out on the WholeFlow server
/// (`GET /api/v1/payments`, internal/appapi/payments.go) and read here.
///
/// Every credit (receipt, return, credit adjustment) settles the **oldest open
/// bill first** (FIFO). A bill is due `creditDays` after its date. The shop's
/// opening balance counts as one bill dated where the synced vouchers begin.
/// Only receipts count as *paying* for the timing figures (days to pay, on
/// time); returns and adjustments still settle bills.

DateTime? _date(Object? v) => v is String && v.isNotEmpty ? DateTime.parse(v) : null;
Money _money(Object? v) => v == null ? Money.zero : Money.parse(v);
double? _double(Object? v) => v is num ? v.toDouble() : null;
int _int(Object? v) => v is num ? v.toInt() : 0;

enum SettleKind {
  payment,
  returned,
  adjustment;

  static SettleKind parse(Object? v) => switch (v) {
    'payment' => payment,
    'returned' => returned,
    _ => adjustment,
  };
}

class Allocation {
  const Allocation(this.date, this.amount, this.kind);

  factory Allocation.fromJson(Map<String, dynamic> j) =>
      Allocation(_date(j['date'])!, _money(j['amount']), SettleKind.parse(j['kind']));

  final DateTime date;
  final Money amount;
  final SettleKind kind;
}

class Bill {
  const Bill({
    required this.date,
    required this.amount,
    required this.due,
    required this.remaining,
    this.voucher,
    this.isOpening = false,
    this.settledOn,
    this.allocations = const [],
  });

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
    date: _date(j['date'])!,
    amount: _money(j['amount']),
    due: _date(j['due'])!,
    remaining: _money(j['remaining']),
    voucher: j['voucher'] as String?,
    isOpening: j['is_opening'] == true,
    settledOn: _date(j['settled_on']),
    allocations: [for (final a in (j['allocations'] as List? ?? const [])) Allocation.fromJson(a as Map<String, dynamic>)],
  );

  final DateTime date;
  final Money amount;
  final DateTime due;
  final String? voucher;
  final bool isOpening;
  final Money remaining;
  final DateTime? settledOn;
  final List<Allocation> allocations;

  bool get isOpen => remaining.isPositive;

  /// Settled by at least one receipt (not only returns/adjustments).
  bool get paidByReceipt => allocations.any((a) => a.kind == SettleKind.payment);

  bool get settledOnTime => settledOn != null && !settledOn!.isAfter(due);

  /// Days past due today (0 when not yet due).
  int daysOverdue(DateTime today) => today.isAfter(due) ? today.difference(due).inDays : 0;
}

/// Ageing of open amounts by days past due.
enum AgeBucket {
  notDue('not_due', 'Not due yet'),
  d1to30('d1_30', '1–30 days late'),
  d31to60('d31_60', '31–60 days late'),
  d61to90('d61_90', '61–90 days late'),
  d90plus('d90_plus', 'Over 90 days late');

  const AgeBucket(this.code, this.label);
  final String code;
  final String label;

  static Map<AgeBucket, Money> parse(Object? json) {
    final m = json is Map ? json : const {};
    return {for (final k in values) k: _money(m[k.code])};
  }
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

/// A shop as the payment analysis sees it.
class PaymentShop {
  const PaymentShop({
    required this.id,
    required this.name,
    this.siteName,
    this.phone,
    required this.opening,
    required this.receivable,
  });

  factory PaymentShop.fromJson(Map<String, dynamic> j) => PaymentShop(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    siteName: j['site_name'] as String?,
    phone: j['phone'] as String?,
    opening: _money(j['opening']),
    receivable: _money(j['receivable']),
  );

  final String id;
  final String name;

  /// Null when the shop is in no site.
  final String? siteName;
  final String? phone;

  /// Signed: Dr (owes) positive.
  final Money opening;
  final Money receivable;
}

/// One shop's payment figures. [bills] is filled only for the shop view
/// (`/payments/shops/{id}`): every unpaid bill and the latest paid ones.
class ShopPaymentProfile {
  const ShopPaymentProfile({
    required this.shop,
    required this.today,
    required this.advance,
    required this.overdue,
    required this.openAmount,
    required this.openBillCount,
    required this.maxDaysOverdue,
    required this.ageing,
    required this.paidBillCount,
    required this.onTimeCount,
    this.oldestOpenBillDate,
    this.onTimeRate,
    this.avgDaysToPay,
    this.avgDaysLate,
    this.lastPaymentDate,
    this.lastPaymentAmount = Money.zero,
    required this.computedBalance,
    required this.reconciled,
    this.bills = const [],
  });

  factory ShopPaymentProfile.fromJson(Map<String, dynamic> j, {required DateTime today}) => ShopPaymentProfile(
    shop: PaymentShop.fromJson(j['shop'] as Map<String, dynamic>),
    today: today,
    advance: _money(j['advance']),
    overdue: _money(j['overdue']),
    openAmount: _money(j['open_amount']),
    openBillCount: _int(j['open_bills']),
    maxDaysOverdue: _int(j['max_days_overdue']),
    oldestOpenBillDate: _date(j['oldest_open_bill_date']),
    ageing: AgeBucket.parse(j['ageing']),
    paidBillCount: _int(j['paid_bills']),
    onTimeCount: _int(j['on_time_bills']),
    onTimeRate: _double(j['on_time_rate']),
    avgDaysToPay: _double(j['avg_days_to_pay']),
    avgDaysLate: _double(j['avg_days_late']),
    lastPaymentDate: _date(j['last_payment_date']),
    lastPaymentAmount: _money(j['last_payment_amount']),
    computedBalance: _money(j['computed_balance']),
    reconciled: j['reconciled'] == true,
    bills: [for (final b in (j['bills'] as List? ?? const [])) Bill.fromJson(b as Map<String, dynamic>)],
  );

  final PaymentShop shop;
  final DateTime today;

  /// Credit not yet used against any bill.
  final Money advance;
  final Money overdue;
  final Money openAmount;
  final int openBillCount;

  /// Days past due of the oldest overdue bill (0 when nothing is overdue).
  final int maxDaysOverdue;
  final DateTime? oldestOpenBillDate;
  final Map<AgeBucket, Money> ageing;

  /// Bills fully settled with at least one receipt, and how many of them by their due date.
  final int paidBillCount;
  final int onTimeCount;

  /// Share of paid bills settled by their due date; null when none are paid yet.
  final double? onTimeRate;

  /// Receipt-weighted average days from bill date to payment; null without receipts.
  final double? avgDaysToPay;

  /// Receipt-weighted average days paid after the due date (early counts as 0).
  final double? avgDaysLate;
  final DateTime? lastPaymentDate;
  final Money lastPaymentAmount;

  /// Open bills minus advance; equals the synced balance when the data is complete.
  final Money computedBalance;
  final bool reconciled;

  /// Oldest first; empty in the company summary.
  final List<Bill> bills;

  List<Bill> get openBills => bills.where((b) => b.isOpen).toList();

  PaymentStatus get status => PaymentStatus.of(maxDaysOverdue);

  PayHabit habit(int creditDays) => PayHabit.of(avgDaysToPay, creditDays);
}

/// One shop's bills under FIFO, for the shop view.
class ShopPayments {
  const ShopPayments({required this.profile, required this.creditDays, required this.closedBills});

  factory ShopPayments.fromJson(Map<String, dynamic> j) {
    final today = _date(j['today']) ?? DateTime.now();
    return ShopPayments(
      profile: ShopPaymentProfile.fromJson(j, today: today),
      creditDays: _int(j['credit_days']),
      closedBills: _int(j['closed_bills']),
    );
  }

  final ShopPaymentProfile profile;
  final int creditDays;

  /// Settled bills in all; [ShopPaymentProfile.bills] has only the latest of them.
  final int closedBills;
}

/// The company's payment figures with one line per shop that has bills.
class BusinessPaymentSummary {
  const BusinessPaymentSummary({
    required this.shops,
    required this.creditDays,
    required this.today,
    required this.overdue,
    required this.overdueShops,
    required this.openAmount,
    required this.ageing,
    this.onTimeRate,
    this.avgDaysToPay,
    this.overdueMonthAgo,
  });

  factory BusinessPaymentSummary.fromJson(Map<String, dynamic> j) {
    final today = _date(j['today']) ?? DateTime.now();
    return BusinessPaymentSummary(
      shops: [
        for (final s in (j['shops'] as List? ?? const [])) ShopPaymentProfile.fromJson(s as Map<String, dynamic>, today: today),
      ],
      creditDays: _int(j['credit_days']),
      today: today,
      overdue: _money(j['overdue']),
      overdueShops: _int(j['overdue_shops']),
      openAmount: _money(j['open_amount']),
      ageing: AgeBucket.parse(j['ageing']),
      onTimeRate: _double(j['on_time_rate']),
      avgDaysToPay: _double(j['avg_days_to_pay']),
      overdueMonthAgo: j['overdue_month_ago'] == null ? null : _money(j['overdue_month_ago']),
    );
  }

  final List<ShopPaymentProfile> shops;
  final int creditDays;
  final DateTime today;
  final Money overdue;
  final int overdueShops;
  final Money openAmount;
  final Map<AgeBucket, Money> ageing;
  final double? onTimeRate;
  final double? avgDaysToPay;

  /// Overdue 30 days ago with the same credit period; null when the books don't reach back that far.
  final Money? overdueMonthAgo;
}
