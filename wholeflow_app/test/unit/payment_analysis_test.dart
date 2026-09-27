import 'package:flutter_test/flutter_test.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/features/analytics/domain/payment_analysis.dart';
import 'package:wholeflow_app/features/shop_detail/domain/statement.dart';

Money rs(num r) => Money((r * 100).round());

PaymentTxn bill(String date, num amount, [String? v]) => PaymentTxn(
  shopId: 's',
  date: DateTime.parse(date),
  category: TxnCategory.sales,
  debit: rs(amount),
  credit: Money.zero,
  voucher: v,
);

PaymentTxn pay(String date, num amount) =>
    PaymentTxn(shopId: 's', date: DateTime.parse(date), category: TxnCategory.receipts, debit: Money.zero, credit: rs(amount));

PaymentTxn ret(String date, num amount) =>
    PaymentTxn(shopId: 's', date: DateTime.parse(date), category: TxnCategory.returns, debit: Money.zero, credit: rs(amount));

ShopOpening shop({num opening = 0, num receivable = 0}) =>
    ShopOpening(id: 's', name: 'Shop', opening: rs(opening), receivable: rs(receivable));

ShopPaymentProfile run(
  List<PaymentTxn> txns, {
  num opening = 0,
  num receivable = 0,
  int days = 30,
  String today = '2026-07-20',
}) => analyseShop(
  shop: shop(opening: opening, receivable: receivable),
  txns: txns,
  creditDays: days,
  booksFrom: DateTime(2026, 4, 1),
  today: DateTime.parse(today),
);

void main() {
  test('payment settles the oldest bill first', () {
    // Bill A 1 Jun ₹10,000 (due 1 Jul), Bill B 15 Jun ₹8,000 (due 15 Jul), ₹12,000 paid 10 Jul.
    final p = run([bill('2026-06-01', 10000, 'A'), bill('2026-06-15', 8000, 'B'), pay('2026-07-10', 12000)], receivable: 6000);
    final a = p.bills[0], b = p.bills[1];
    expect(a.isOpen, isFalse);
    expect(a.settledOn, DateTime(2026, 7, 10));
    expect(a.settledOnTime, isFalse); // 9 days late
    expect(b.remaining, rs(6000));
    expect(b.daysOverdue(DateTime(2026, 7, 20)), 5);
    expect(p.overdue, rs(6000));
    expect(p.maxDaysOverdue, 5);
    expect(p.onTimeRate, 0);
    expect(p.reconciled, isTrue);
    // ₹10,000 paid after 39 days, ₹2,000 after 25 days.
    expect(p.avgDaysToPay, closeTo((10000 * 39 + 2000 * 25) / 12000, 1e-9));
    expect(p.avgDaysLate, closeTo((10000 * 9 + 2000 * 0) / 12000, 1e-9));
    expect(p.lastPaymentDate, DateTime(2026, 7, 10));
  });

  test('changing the credit days changes what is late', () {
    final txns = [bill('2026-06-01', 10000), pay('2026-07-10', 10000)];
    expect(run(txns, days: 30).onTimeRate, 0);
    expect(run(txns, days: 45).onTimeRate, 1);
  });

  test('opening balance is the oldest bill', () {
    final p = run([bill('2026-05-01', 1000), pay('2026-05-10', 1500)], opening: 2000, receivable: 1500);
    expect(p.bills.first.isOpening, isTrue);
    expect(p.bills.first.date, DateTime(2026, 4, 1));
    expect(p.bills.first.remaining, rs(500));
    expect(p.bills[1].remaining, rs(1000));
    expect(p.reconciled, isTrue);
  });

  test('Cr opening balance and early payments are advances used by later bills', () {
    final p = run([pay('2026-05-01', 300), bill('2026-05-20', 1000)], opening: -200, receivable: 500);
    final b = p.bills.single;
    expect(b.remaining, rs(500));
    expect(b.allocations.map((a) => a.kind), [SettleKind.adjustment, SettleKind.payment]);
    expect(p.avgDaysToPay, 0); // paid before the bill counts as same day
    expect(p.advance, Money.zero);
  });

  test('returns settle bills but do not count as paying', () {
    final p = run([bill('2026-06-01', 1000), ret('2026-06-05', 1000)]);
    expect(p.bills.single.isOpen, isFalse);
    expect(p.paidBills, isEmpty);
    expect(p.onTimeRate, isNull);
    expect(p.avgDaysToPay, isNull);
  });

  test('same-day bill and payment: bill is recorded first', () {
    final p = run([pay('2026-06-01', 1000), bill('2026-06-01', 1000)]);
    expect(p.bills.single.isOpen, isFalse);
    expect(p.bills.single.allocations.single.kind, SettleKind.payment);
    expect(p.advance, Money.zero);
  });

  test('ageing buckets by days past due', () {
    final p = run([
      bill('2026-07-10', 100),
      bill('2026-06-10', 200),
      bill('2026-05-10', 300),
      bill('2026-03-01', 400),
    ], today: '2026-07-20');
    final a = p.ageing;
    expect(a[AgeBucket.notDue], rs(100)); // due 9 Aug
    expect(a[AgeBucket.d1to30], rs(200)); // due 10 Jul, 10 days late
    expect(a[AgeBucket.d31to60], rs(300)); // due 9 Jun, 41 days late
    expect(a[AgeBucket.d90plus], rs(400)); // due 31 Mar
    expect(p.status, PaymentStatus.veryLate);
  });

  test('business summary adds up shops', () {
    final s = analyseBusiness(
      shops: [
        const ShopOpening(id: 'a', name: 'A', opening: Money.zero, receivable: Money(100000)),
        const ShopOpening(id: 'b', name: 'B', opening: Money.zero, receivable: Money.zero),
        const ShopOpening(id: 'c', name: 'Idle', opening: Money.zero, receivable: Money.zero),
      ],
      txns: [
        PaymentTxn(shopId: 'a', date: DateTime(2026, 5, 1), category: TxnCategory.sales, debit: rs(1000), credit: Money.zero),
        PaymentTxn(shopId: 'b', date: DateTime(2026, 5, 1), category: TxnCategory.sales, debit: rs(500), credit: Money.zero),
        PaymentTxn(shopId: 'b', date: DateTime(2026, 5, 11), category: TxnCategory.receipts, debit: Money.zero, credit: rs(500)),
      ],
      creditDays: 30,
      booksFrom: DateTime(2026, 4, 1),
      today: DateTime(2026, 7, 20),
    );
    expect(s.shops.map((p) => p.shop.id), ['a', 'b']); // idle shop left out
    expect(s.overdue, rs(1000));
    expect(s.overdueShops, 1);
    expect(s.onTimeRate, 1);
    expect(s.avgDaysToPay, 10);
  });
}
